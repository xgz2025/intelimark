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
import os
import GRDB
import Model
import Capture

/// Moves committed captures from the Inbox into the library and queues enrichment.
/// Idempotent: the item ID is the envelope ID, so a crash mid-way just re-ingests.
public struct Ingestor: Sendable {
    public let store: EnvelopeStore
    public let database: LibraryDatabase
    public let itemsDirectory: URL

    public init(store: EnvelopeStore, database: LibraryDatabase, itemsDirectory: URL) {
        self.store = store
        self.database = database
        self.itemsDirectory = itemsDirectory
    }

    static let logger = Logger(subsystem: "com.veloworkspaces.nextmark", category: "ingest")

    /// Ingests every committed capture, oldest first. Returns the new item IDs.
    @discardableResult
    public func ingestPending(now: Date = Date()) async throws -> [String] {
        try await ingestPendingReportingFailures(now: now).ingested
    }

    /// Like `ingestPending`, and says why the last capture that couldn't be added failed.
    public func ingestPendingReportingFailures(now: Date = Date()) async throws -> (ingested: [String], lastFailure: (any Error)?) {
        var ingested: [String] = []
        var lastFailure: (any Error)?
        for capture in try store.committedCaptures() {
            // One capture that fails (e.g. its files can't be moved) stays in the Inbox for
            // the next pass; it doesn't hold up the others.
            do {
                ingested.append(try await ingest(capture, now: now))
            } catch {
                Self.logger.error("Couldn't add capture \(capture.envelope.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                lastFailure = error
            }
        }
        try store.collectGarbage(now: now)
        return (ingested, lastFailure)
    }

    /// Saves still waiting in the Inbox after a pass: the ones that couldn't be added.
    /// Ones committed in the last minute are left out; they may simply have arrived
    /// during the pass.
    public func waitingCount(now: Date = Date()) -> Int {
        let captures = (try? store.committedCaptures()) ?? []
        return captures.filter { now.timeIntervalSince($0.envelope.id.date) > 60 }.count
    }

    /// Returns the ID of the item the capture became, or refreshed.
    @discardableResult
    func ingest(_ capture: CommittedCapture, now: Date) async throws -> String {
        let envelope = capture.envelope
        if let refreshed = try await refreshProduct(with: envelope, now: now) {
            try store.discard(envelope.id)
            return refreshed
        }
        let itemID = envelope.id.rawValue
        let attachments = try moveAttachments(of: capture, itemID: itemID)
        let item = ItemRecord(envelope: envelope, now: now)

        try await database.writer.write { db in
            guard try ItemRecord.fetchOne(db, key: itemID) == nil else { return }
            try item.insert(db)
            for attachment in attachments {
                try attachment.insert(db)
            }
            var job = JobRecord(itemID: itemID, stage: .extract, notBefore: now)
            try job.insert(db)
        }
        try store.discard(envelope.id)
        return itemID
    }

    /// A product page saved again (Safari's Laterwise button, or Share) refreshes the
    /// product already saved, rather than making a second one: the page as the person
    /// sees it now is read again for its price (Docs/save_types.md). A highlight, a
    /// note or a file is a new save.
    func refreshProduct(with envelope: CaptureEnvelope, now: Date) async throws -> String? {
        guard envelope.selection == nil, envelope.userNote == nil, envelope.payloadFiles.isEmpty,
              envelope.surface != .screenshotImport
        else { return nil }
        let keys = Set([envelope.url, envelope.pageContext?.canonicalURL].compactMap { ProductURL.key($0) })
        guard !keys.isEmpty else { return nil }
        return try await database.writer.write { db -> String? in
            let products = try ItemRecord
                .filter(Column("status") != ItemStatus.trashed.rawValue)
                .filter(Column("canonicalURL") != nil)
                .filter(Column("typedFields").like("%\"product\"%"))
                .fetchAll(db)
            guard var item = products.first(where: { product in
                product.saveType == .product && ProductURL.key(product.canonicalURL.flatMap { URL(string: $0) }).map(keys.contains) == true
            }) else { return nil }
            // The page as seen now; without one (a shopping app's share), the page is
            // fetched again, with the price in the shared text to fall back on.
            item.pageContext = envelope.pageContext
            if let text = envelope.text, item.anchor == nil { item.text = text }
            if let intent = envelope.userIntent { item.intent = intent }
            item.updatedAt = now
            try item.update(db)
            let pending = try JobRecord.filter(Column("itemID") == item.id && Column("stage") == PipelineStage.extract.rawValue).fetchCount(db)
            if pending == 0 {
                var job = JobRecord(itemID: item.id, stage: .extract, notBefore: now)
                try job.insert(db)
            }
            return item.id
        }
    }

    private func moveAttachments(of capture: CommittedCapture, itemID: String) throws -> [AttachmentRecord] {
        let files = capture.envelope.payloadFiles
        guard !files.isEmpty else { return [] }
        let directory = itemsDirectory.appending(path: itemID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try files.enumerated().map { index, file in
            let source = capture.payloadURL(for: file)
            let destination = directory.appending(path: file.fileName)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: source.path(percentEncoded: false)),
               !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.moveItem(at: source, to: destination)
            }
            return AttachmentRecord(
                itemID: itemID,
                index: index,
                role: .original,
                fileName: file.fileName,
                contentType: file.contentType,
                byteSize: file.byteSize,
                syncPolicy: .ifEnabled
            )
        }
    }
}
