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

    /// Takes the next due job and counts the attempt *before* it runs: its attempt
    /// count goes up and it's put off by the backoff (1, 2, 4… minutes, capped at 6 h).
    /// A job that ends the app (out of memory, a crash in a system framework) is then
    /// not run again at once on every launch, and a job whose completion can't be
    /// written (storage full) isn't picked again in a loop. `complete` removes it.
    public func claimNext(now: Date = Date()) async throws -> JobRecord? {
        try await database.writer.write { db in
            guard var job = try JobRecord
                .filter(Column("notBefore") <= now)
                .order(Column("notBefore"), Column("id"))
                .fetchOne(db)
            else { return nil }
            job.attempts += 1
            job.notBefore = now.addingTimeInterval(Self.backoff(afterAttempts: job.attempts))
            try job.update(db)
            return job
        }
    }

    static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        min(pow(2, Double(max(attempts, 1) - 1)) * 60, 6 * 60 * 60)
    }

    /// Makes postponed jobs of `stage` due now (e.g. fetches, once back online).
    public func makeDue(_ stage: PipelineStage, now: Date = Date()) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE job SET notBefore = ? WHERE stage = ? AND notBefore > ?",
                arguments: [now, stage.rawValue, now]
            )
        }
    }

    /// When the next job is due, to wake the pipeline then.
    public func nextDueDate() async throws -> Date? {
        try await database.writer.read { db in
            try Date.fetchOne(db, sql: "SELECT MIN(notBefore) FROM job")
        }
    }

    public func hasJob(forItem itemID: String) async throws -> Bool {
        try await database.writer.read { db in
            try JobRecord.filter(Column("itemID") == itemID).fetchCount(db) > 0
        }
    }

    public func count() async throws -> Int {
        try await database.writer.read { db in try JobRecord.fetchCount(db) }
    }
}
