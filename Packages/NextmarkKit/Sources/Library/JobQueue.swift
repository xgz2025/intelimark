import Foundation
import GRDB
import Model

/// The persistent enrichment queue (Docs/architecture.md §5.1). Survives the app
/// being killed; any device may run it because every stage is idempotent.
public struct JobQueue: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func enqueue(_ stage: PipelineStage, itemID: String, notBefore: Date = Date()) async throws {
        try await database.writer.write { db in
            var job = JobRecord(itemID: itemID, stage: stage, notBefore: notBefore)
            try job.insert(db)
        }
    }

    public func next(now: Date = Date()) async throws -> JobRecord? {
        try await database.writer.read { db in
            try JobRecord
                .filter(Column("notBefore") <= now)
                .order(Column("notBefore"), Column("id"))
                .fetchOne(db)
        }
    }

    public func complete(_ job: JobRecord) async throws {
        guard let id = job.id else { return }
        _ = try await database.writer.write { db in try JobRecord.deleteOne(db, key: id) }
    }

    /// Exponential backoff (1, 2, 4… minutes, capped at 6 h); gives up after `maxAttempts`.
    /// Returns `false` when it gave up and removed the job.
    @discardableResult
    public func retry(_ job: JobRecord, now: Date = Date(), maxAttempts: Int = 5) async throws -> Bool {
        try await database.writer.write { db in
            var job = job
            job.attempts += 1
            guard job.attempts < maxAttempts else {
                _ = try job.delete(db)
                return false
            }
            job.notBefore = now.addingTimeInterval(min(pow(2, Double(job.attempts - 1)) * 60, 6 * 60 * 60))
            try job.update(db)
            return true
        }
    }

    public func count() async throws -> Int {
        try await database.writer.read { db in try JobRecord.fetchCount(db) }
    }
}
