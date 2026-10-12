//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import Foundation
import CloudKit
import Security
import os
import Library

/// iCloud sync through CKSyncEngine (Docs/architecture.md §4.3, PRD P1, P2). The
/// engine schedules sends and fetches, listens for pushes and retries; this actor
/// hands it records from `SyncStore` and writes what it fetches back.
public actor CloudSync: CKSyncEngineDelegate {
    public static let containerIdentifier = "iCloud.com.nextmark.app"
    static let batchSize = 200

    private let store: SyncStore
    private let containerIdentifier: String
    private let onChange: @Sendable (SyncApplyResult) async -> Void
    private let logger = Logger(subsystem: "com.nextmark.app", category: "sync")

    private var engine: CKSyncEngine?
    private var isStarting = false
    /// What the settings last asked for; `start()` checks it again after awaiting.
    private var wantsToRun = false
    private var observation: Task<Void, Never>?
    /// The last change handed to the engine; later ones are added as they happen.
    private var enqueuedSeq: Int64 = 0
    /// The change each record in flight carries, so a save only clears that change.
    private var inFlight: [RecordKey: Int64] = [:]
    private var syncedOriginals: Bool?

    /// - Parameter onChange: called after records from other devices were written.
    public init(
        store: SyncStore,
        containerIdentifier: String = CloudSync.containerIdentifier,
        onChange: @escaping @Sendable (SyncApplyResult) async -> Void
    ) {
        self.store = store
        self.containerIdentifier = containerIdentifier
        self.onChange = onChange
    }

    /// Unsigned builds have no iCloud entitlement, and CloudKit traps without one.
    public static var isAvailable: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
        #else
        return true
        #endif
    }

    /// Starts or stops syncing to match the user's settings. Cheap to call often.
    public func update(enabled: Bool, originals: Bool) async {
        wantsToRun = enabled && Self.isAvailable
        guard wantsToRun else {
            stop()
            if !Self.isAvailable { setStatus(String(localized: "This build isn't signed for iCloud.")) }
            return
        }
        if let previous = syncedOriginals, !previous, originals {
            // Files left behind while the setting was off go up now.
            try? await store.markAllChanged(recordTypes: ["Attachment"])
        }
        syncedOriginals = originals
        await start()
    }

    func start() async {
        // `update` can be called again while this awaits; start one engine only.
        guard engine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let container = CKContainer(identifier: containerIdentifier)
        let serialization = (try? await store.engineState())
            .flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        // Turned off while this was waiting.
        guard wantsToRun else { return }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if serialization == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoder.zoneID))])
        }
        enqueuedSeq = 0
        await enqueuePending()

        let changes = store.changeCounter()
        observation = Task { [weak self] in
            do {
                for try await _ in changes {
                    await self?.enqueuePending()
                }
            } catch {}
        }

        if let status = try? await container.accountStatus(), status != .available {
            setStatus(String(localized: "Sign in to iCloud to sync your library."))
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        engine = nil
        inFlight = [:]
    }

    /// Fetches and sends now, e.g. from "Sync Now" in Settings.
    public func syncNow() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            markSynced()
        } catch {
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            setStatus(error.localizedDescription)
        }
    }

    /// Hands new local changes to the engine.
    private func enqueuePending() async {
        guard let engine, let pending = try? await store.pendingChanges(after: enqueuedSeq), !pending.isEmpty else { return }
        enqueuedSeq = pending.map(\.seq).max() ?? enqueuedSeq
        let existing = Set(engine.state.pendingRecordZoneChanges)
        let changes = pending.map { change -> CKSyncEngine.PendingRecordZoneChange in
            let id = CloudRecordCoder.recordID(for: change.key)
            return change.isDeletion ? .deleteRecord(id) : .saveRecord(id)
        }.filter { !existing.contains($0) }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    // MARK: CKSyncEngineDelegate

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = Array(syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }.prefix(Self.batchSize))
        guard !pending.isEmpty else { return nil }

        let keys = pending.compactMap { change -> RecordKey? in
            switch change {
            case .saveRecord(let id), .deleteRecord(let id):
                return CloudRecordCoder.key(for: id)
            @unknown default:
                return nil
            }
        }
        guard let outgoing = try? await store.outgoing(keys) else { return nil }
        let changes = Dictionary(outgoing.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        var records: [CKRecord.ID: CKRecord] = [:]
        var send: [CKSyncEngine.PendingRecordZoneChange] = []
        var stale: [CKSyncEngine.PendingRecordZoneChange] = []
        var nothingToSend: [OutgoingChange] = []
        for pendingChange in pending {
            switch pendingChange {
            case .saveRecord(let id):
                guard let key = CloudRecordCoder.key(for: id), let change = changes[key], !change.isDeletion else {
                    stale.append(pendingChange)
                    continue
                }
                guard let record = change.record, let ckRecord = try? CloudRecordCoder.ckRecord(from: record) else {
                    stale.append(pendingChange)
                    nothingToSend.append(change)
                    continue
                }
                records[id] = ckRecord
                inFlight[key] = change.seq
                send.append(pendingChange)
            case .deleteRecord(let id):
                guard let key = CloudRecordCoder.key(for: id), let change = changes[key], change.isDeletion else {
                    stale.append(pendingChange)
                    continue
                }
                inFlight[key] = change.seq
                send.append(pendingChange)
            @unknown default:
                stale.append(pendingChange)
            }
        }
        if !stale.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: stale) }
        try? await store.discard(nothingToSend)
        guard !send.isEmpty else { return nil }

        let provided = Records(byID: records)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: send) { provided.byID[$0] }
    }

    /// Built before the batch asks for them; read-only afterwards.
    private struct Records: @unchecked Sendable {
        let byID: [CKRecord.ID: CKRecord]
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                try? await store.saveEngineState(data)
            }

        case .accountChange(let change):
            await handleAccountChange(change, syncEngine: syncEngine)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == CloudRecordCoder.zoneID {
                await handleZoneDeletion(deletion.reason, syncEngine: syncEngine)
            }

        case .fetchedRecordZoneChanges(let changes):
            let records = changes.modifications.compactMap { try? CloudRecordCoder.syncRecord(from: $0.record) }
            let deletions = changes.deletions.compactMap { CloudRecordCoder.key(for: $0.recordID) }
            do {
                let result = try await store.apply(records, deletions: deletions)
                if !result.isEmpty { notify(result) }
            } catch {
                logger.error("Couldn't apply fetched changes: \(error.localizedDescription, privacy: .public)")
            }

        case .sentRecordZoneChanges(let sent):
            await handleSentChanges(sent, syncEngine: syncEngine)

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                logger.error("Couldn't create the zone: \(failure.error.localizedDescription, privacy: .public)")
            }

        case .didFetchChanges, .didSendChanges:
            markSynced()

        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willSendChanges:
            break

        @unknown default:
            break
        }
    }

    /// The app's follow-up (embedding, enrichment) runs on its own; the engine handles
    /// its events one at a time and shouldn't wait for it.
    private func notify(_ result: SyncApplyResult) {
        let onChange = onChange
        Task { await onChange(result) }
    }

    private func handleSentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) async {
        var saved: [SentChange] = []
        var deleted: [SentChange] = []
        var conflicts: [SyncRecord] = []
        var forgotten: [RecordKey] = []
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false

        for record in sent.savedRecords {
            guard let key = CloudRecordCoder.key(for: record.recordID) else { continue }
            let seq = inFlight.removeValue(forKey: key) ?? 0
            saved.append(SentChange(key: key, seq: seq, systemFields: CloudRecordCoder.systemFields(of: record)))
        }
        for recordID in sent.deletedRecordIDs {
            guard let key = CloudRecordCoder.key(for: recordID) else { continue }
            deleted.append(SentChange(key: key, seq: inFlight.removeValue(forKey: key) ?? 0, systemFields: nil))
        }
        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            guard let key = CloudRecordCoder.key(for: recordID) else { continue }
            inFlight[key] = nil
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device got there first: merge, and send the merge if it differs.
                if let server = failure.error.serverRecord, let record = try? CloudRecordCoder.syncRecord(from: server) {
                    conflicts.append(record)
                }
            case .zoneNotFound:
                needsZone = true
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // The server no longer has it: send it as a new record.
                forgotten.append(key)
                retry.append(.saveRecord(recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                 .notAuthenticated, .operationCancelled:
                break   // the engine tries again
            default:
                logger.error("Couldn't save \(key, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
            }
        }
        for (recordID, error) in sent.failedRecordDeletes {
            guard let key = CloudRecordCoder.key(for: recordID) else { continue }
            let seq = inFlight.removeValue(forKey: key) ?? 0
            if error.code == .unknownItem {
                deleted.append(SentChange(key: key, seq: seq, systemFields: nil))
            }
        }

        do {
            try await store.didSend(saved: saved, deleted: deleted)
            try await store.forgetSystemFields(forgotten)
            if !conflicts.isEmpty {
                let result = try await store.apply(conflicts)
                if !result.isEmpty { notify(result) }
            }
        } catch {
            logger.error("Couldn't record sent changes: \(error.localizedDescription, privacy: .public)")
        }
        if needsZone {
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoder.zoneID))])
        }
        if !retry.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: retry)
        }
        // A record edited again while it was uploading still has a change waiting, but the
        // engine has just dropped it as sent: look at every pending change, not only new ones.
        enqueuedSeq = 0
        await enqueuePending()
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange, syncEngine: CKSyncEngine) async {
        switch change.changeType {
        case .signIn, .switchAccounts:
            // Everything goes up to the account now signed in; local data stays.
            try? await store.resetServerState()
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoder.zoneID))])
            enqueuedSeq = 0
            setStatus("")
            await enqueuePending()
        case .signOut:
            try? await store.resetServerState()
            setStatus(String(localized: "Sign in to iCloud to sync your library."))
        @unknown default:
            break
        }
    }

    private func handleZoneDeletion(_ reason: CKDatabase.DatabaseChange.Deletion.Reason, syncEngine: CKSyncEngine) async {
        try? await store.resetServerState()
        switch reason {
        case .purged:
            // The user deleted Nextmark's iCloud data in Settings: stop until they turn sync back on.
            UserDefaults.standard.set(false, forKey: SyncSettings.Key.enabled)
            setStatus(String(localized: "Your iCloud data was deleted. Turn sync on to upload your library again."))
            stop()
        case .deleted, .encryptedDataReset:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoder.zoneID))])
            enqueuedSeq = 0
            await enqueuePending()
        @unknown default:
            break
        }
    }

    // MARK: Status (shown in Settings)

    private func markSynced() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: SyncSettings.Key.lastSyncedAt)
        UserDefaults.standard.set("", forKey: SyncSettings.Key.status)
    }

    private func setStatus(_ status: String) {
        UserDefaults.standard.set(status, forKey: SyncSettings.Key.status)
    }
}
