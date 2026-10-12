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
import GRDB
import Model
import Library
@testable import Sync

/// A stand-in for the CloudKit private database: change tags, conflicts, a change
/// feed and files. Like the real one, it serves back the records a device saved itself.
actor FakeCloud {
    enum SaveResult {
        case saved(SyncRecord)
        case conflict(SyncRecord)
    }

    private struct Stored {
        var record: SyncRecord
        var tag: Int
        var file: Data?
        var change: Int
    }

    private var stored: [RecordKey: Stored] = [:]
    private var deletions: [RecordKey: Int] = [:]
    /// Advances with every save and deletion.
    private(set) var clock = 0
    let filesDirectory: URL

    init(filesDirectory: URL) {
        self.filesDirectory = filesDirectory
    }

    var recordCount: Int { stored.count }

    func record(_ key: RecordKey) -> SyncRecord? { stored[key]?.record }

    func hasFile(_ key: RecordKey) -> Bool { stored[key]?.file != nil }

    func save(_ record: SyncRecord) -> SaveResult {
        let sentTag = record.systemFields.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
        if let existing = stored[record.key], existing.tag != sentTag {
            return .conflict(served(existing))
        }
        clock += 1
        let tag = (stored[record.key]?.tag ?? 0) + 1
        var saved = record
        saved.systemFields = Data(String(tag).utf8)
        saved.fileURL = nil
        let file = record.fileURL.flatMap { try? Data(contentsOf: $0) } ?? stored[record.key]?.file
        stored[record.key] = Stored(record: saved, tag: tag, file: file, change: clock)
        deletions[record.key] = nil
        return .saved(saved)
    }

    func delete(_ key: RecordKey) {
        clock += 1
        stored[key] = nil
        deletions[key] = clock
    }

    func changes(since token: Int) -> (records: [SyncRecord], deletions: [RecordKey], token: Int) {
        let records = stored.values.filter { $0.change > token }.sorted { $0.change < $1.change }.map { served($0) }
        let deleted = deletions.filter { $0.value > token }.map(\.key)
        return (records, deleted, clock)
    }

    private func served(_ stored: Stored) -> SyncRecord {
        var record = stored.record
        if let file = stored.file {
            let url = filesDirectory.appending(path: UUID().uuidString)
            try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            try? file.write(to: url)
            record.fileURL = url
        }
        return record
    }
}

/// One device: its own database and files, synced through a `FakeCloud` the way
/// `CloudSync` drives CKSyncEngine. Used from one test at a time.
final class TestDevice: @unchecked Sendable {
    let name: String
    let database: LibraryDatabase
    let store: SyncStore
    let itemsDirectory: URL
    private var token = 0

    init(_ name: String, root: URL, originals: Bool = true) throws {
        self.name = name
        database = try LibraryDatabase.inMemory()
        itemsDirectory = root.appending(path: name, directoryHint: .isDirectory)
        store = SyncStore(database: database, itemsDirectory: itemsDirectory, syncsOriginals: { originals })
    }

    var items: ItemRepository { ItemRepository(database: database) }
    var groups: GroupRepository { GroupRepository(database: database) }
    var actions: ActionRepository { ActionRepository(database: database) }

    /// Sends what's pending (merging conflicts, as CloudSync does), then fetches what's new.
    @discardableResult
    func sync(with cloud: FakeCloud) async throws -> SyncApplyResult {
        var result = SyncApplyResult()
        for _ in 0..<5 {
            let outgoing = try await store.outgoing()
            guard !outgoing.isEmpty else { break }
            var saved: [SentChange] = []
            var deleted: [SentChange] = []
            var nothingToSend: [OutgoingChange] = []
            var conflicts: [SyncRecord] = []
            for change in outgoing {
                if change.isDeletion {
                    await cloud.delete(change.key)
                    deleted.append(SentChange(key: change.key, seq: change.seq, systemFields: nil))
                } else if let record = change.record {
                    switch await cloud.save(record) {
                    case .saved(let server):
                        saved.append(SentChange(key: change.key, seq: change.seq, systemFields: server.systemFields))
                    case .conflict(let server):
                        conflicts.append(server)
                    }
                } else {
                    nothingToSend.append(change)
                }
            }
            try await store.didSend(saved: saved, deleted: deleted)
            try await store.discard(nothingToSend)
            result.merge(try await store.apply(conflicts))
        }
        let changes = await cloud.changes(since: token)
        token = changes.token
        result.merge(try await store.apply(changes.records, deletions: changes.deletions))
        return result
    }

    func pending() async throws -> [PendingChange] {
        try await store.pendingChanges()
    }

    /// A captured item, optionally with files saved next to it.
    @discardableResult
    func addItem(
        _ title: String, note: String? = nil, scope: SyncScope = .cloud, files: [String: Data] = [:]
    ) async throws -> String {
        let id = ULID()
        var draft = ItemRecord(envelope: CaptureEnvelope(id: id, device: name, surface: .shareSheet, title: title, userNote: note))
        draft.syncScope = scope
        let item = draft
        let directory = itemsDirectory.appending(path: id.rawValue, directoryHint: .isDirectory)
        var attachments: [AttachmentRecord] = []
        for (index, (fileName, data)) in files.sorted(by: { $0.key < $1.key }).enumerated() {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: fileName))
            attachments.append(AttachmentRecord(
                itemID: id.rawValue, index: index, role: .original, fileName: fileName,
                contentType: "com.adobe.pdf", byteSize: Int64(data.count), syncPolicy: .ifEnabled
            ))
        }
        let toInsert = attachments
        try await database.writer.write { db in
            try item.insert(db)
            for attachment in toInsert { try attachment.insert(db) }
        }
        return id.rawValue
    }

    func execute(_ sql: String, _ arguments: StatementArguments = []) async throws {
        try await database.writer.write { db in try db.execute(sql: sql, arguments: arguments) }
    }

    func fieldTimes(_ key: RecordKey) async throws -> [String: String] {
        let json = try await database.writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT times FROM syncStamp WHERE recordType = ? AND recordName = ?",
                arguments: [key.recordType, key.recordName]
            )
        }
        return SyncMerge.times(["syncFieldTimes": .text(json ?? "{}")])
    }
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// Stamps are written with millisecond precision; edits in a test can be closer than that.
func nextMillisecond() async throws {
    try await Task.sleep(for: .milliseconds(3))
}
