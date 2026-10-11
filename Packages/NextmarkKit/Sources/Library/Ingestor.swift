import Foundation
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

    /// Ingests every committed capture, oldest first. Returns the new item IDs.
    @discardableResult
    public func ingestPending(now: Date = Date()) async throws -> [String] {
        var ingested: [String] = []
        for capture in try store.committedCaptures() {
            try await ingest(capture, now: now)
            ingested.append(capture.envelope.id.rawValue)
        }
        try store.collectGarbage(now: now)
        return ingested
    }

    func ingest(_ capture: CommittedCapture, now: Date) async throws {
        let envelope = capture.envelope
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
