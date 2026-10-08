import Foundation
import GRDB
import Model

/// Reads and writes items. UI code observes through `AsyncThrowingStream`s so
/// feature modules never import GRDB.
public struct ItemRepository: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func item(id: String) async throws -> ItemRecord? {
        try await database.writer.read { db in try ItemRecord.fetchOne(db, key: id) }
    }

    /// Live list of items with the given statuses, newest first.
    public func items(withStatus statuses: [ItemStatus] = [.inbox, .active]) -> AsyncThrowingStream<[ItemRecord], any Error> {
        let database = database
        let rawStatuses = statuses.map(\.rawValue)
        return AsyncThrowingStream { continuation in
            let task = Task {
                let observation = ValueObservation.tracking { db in
                    try ItemRecord
                        .filter(rawStatuses.contains(Column("status")))
                        .order(Column("createdAt").desc)
                        .fetchAll(db)
                }
                do {
                    for try await items in observation.values(in: database.writer) {
                        continuation.yield(items)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Full-text search with prefix matching, ranked by BM25. The semantic half of
    /// hybrid search (Docs/architecture.md §9) joins in with the Embed stage.
    public func search(_ query: String, limit: Int = 50) async throws -> [ItemRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await database.writer.read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else { return [] }
            return try ItemRecord.fetchAll(
                db,
                sql: """
                    SELECT item.* FROM item
                    JOIN item_fts ON item_fts.rowid = item.rowid
                    WHERE item_fts MATCH ? AND item.status <> 'trashed'
                    ORDER BY bm25(item_fts)
                    LIMIT ?
                    """,
                arguments: [pattern, limit]
            )
        }
    }

    /// Writes the Understand stage's output into the derived layer only, so a user
    /// edit made while the model was running is never overwritten.
    public func applyUnderstanding(_ understanding: Understanding, toItem id: String, version: Int, now: Date = Date()) async throws {
        let keywords = String(decoding: try JSONEncoder().encode(understanding.keywords), as: UTF8.self)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE item
                    SET aiTitle = ?, summary = ?, semanticKind = ?, suggestedIntent = ?,
                        keywords = ?, derivedVersion = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    understanding.title, understanding.summary, understanding.semanticKind.rawValue,
                    understanding.likelyIntent?.rawValue, keywords, version, now, id,
                ]
            )
        }
    }
}
