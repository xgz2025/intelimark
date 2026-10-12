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

/// The storage half of hybrid search (Docs/architecture.md §9): full-text matches,
/// vectors for the semantic scan, and the filters both share. Ranking and fusion
/// live in the `Search` module.
extension ItemRepository {
    /// Full-text search with prefix matching, ranked by BM25.
    public func search(_ text: String, limit: Int = 50) async throws -> [ItemRecord] {
        let ids = try await lexicalMatches(for: SearchQuery(text: text), limit: limit)
        return try await items(ids: ids)
    }

    /// IDs of items whose text matches every word of the query (as prefixes) and
    /// that pass its filters, best BM25 match first.
    public func lexicalMatches(for query: SearchQuery, limit: Int = 100) async throws -> [String] {
        let text = query.trimmedText
        guard !text.isEmpty else { return [] }
        return try await database.writer.read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return [] }
            let filter = Self.filterSQL(query)
            return try String.fetchAll(
                db,
                sql: """
                    SELECT item.id FROM item
                    JOIN item_fts ON item_fts.rowid = item.rowid
                    WHERE item_fts MATCH ? AND \(filter.sql)
                    ORDER BY bm25(item_fts)
                    LIMIT ?
                    """,
                arguments: StatementArguments([pattern.databaseValue] + filter.values + [limit.databaseValue])
            )
        }
    }

    /// IDs of items that pass the query's filters, newest first: what search shows
    /// before anything is typed.
    public func recentMatches(for query: SearchQuery, limit: Int = 100) async throws -> [String] {
        try await database.writer.read { db in
            let filter = Self.filterSQL(query)
            return try String.fetchAll(
                db,
                sql: "SELECT item.id FROM item WHERE \(filter.sql) ORDER BY item.createdAt DESC LIMIT ?",
                arguments: StatementArguments(filter.values + [limit.databaseValue])
            )
        }
    }

    /// Vectors from one embedding model for the items that pass the query's filters.
    public func vectors(modelID: String, matching query: SearchQuery) async throws -> [StoredVector] {
        try await database.writer.read { db in
            let filter = Self.filterSQL(query)
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT embedding.itemID, embedding.vector FROM embedding
                    JOIN item ON item.id = embedding.itemID
                    WHERE embedding.modelID = ? AND \(filter.sql)
                    """,
                arguments: StatementArguments([modelID.databaseValue] + filter.values)
            )
            return rows.map { row in
                let itemID: String = row["itemID"]
                let blob: Data = row["vector"]
                return StoredVector(itemID: itemID, vector: VectorBlob.decode(blob))
            }
        }
    }

    /// Items in the order of `ids`; IDs of deleted items are skipped.
    public func items(ids: [String]) async throws -> [ItemRecord] {
        guard !ids.isEmpty else { return [] }
        let records = try await database.writer.read { db in try ItemRecord.fetchAll(db, keys: ids) }
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    // MARK: Embeddings

    /// Stores an item's vector, replacing any from an earlier model.
    public func saveEmbedding(_ vector: [Float], modelID: String, forItem id: String) async throws {
        try await database.writer.write { db in
            guard try ItemRecord.exists(db, key: id) else { return }
            try EmbeddingRecord.filter(Column("itemID") == id).deleteAll(db)
            try EmbeddingRecord(itemID: id, modelID: modelID, vector: vector).insert(db)
        }
    }

    public func embedding(forItem id: String) async throws -> EmbeddingRecord? {
        try await database.writer.read { db in
            try EmbeddingRecord.filter(Column("itemID") == id).fetchOne(db)
        }
    }

    /// The embedding models that have stored vectors.
    public func embeddingModelIDs() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT modelID FROM embedding ORDER BY modelID")
        }
    }

    /// Items to embed (again): those without a vector, plus those whose vector came
    /// from one of `staleModelIDs` (e.g. a model revision replaced by an OS update).
    /// Items with a pending job are skipped; the pipeline embeds them anyway.
    public func itemIDsNeedingEmbedding(staleModelIDs: [String] = [], limit: Int = 200) async throws -> [String] {
        try await database.writer.read { db in
            let stale = staleModelIDs.isEmpty ? "0" : "embedding.modelID IN (\(Self.placeholders(staleModelIDs.count)))"
            return try String.fetchAll(
                db,
                sql: """
                    SELECT item.id FROM item
                    LEFT JOIN embedding ON embedding.itemID = item.id
                    WHERE item.status <> 'trashed'
                      AND (embedding.itemID IS NULL OR \(stale))
                      AND NOT EXISTS (SELECT 1 FROM job WHERE job.itemID = item.id)
                      AND \(LibraryDatabase.notSkipped(.embed, column: "item.id"))
                    ORDER BY item.createdAt DESC
                    LIMIT ?
                    """,
                arguments: StatementArguments(
                    staleModelIDs.map(\.databaseValue) + [LibraryDatabase.osVersion.databaseValue, limit.databaseValue]
                )
            )
        }
    }

    // MARK: Filters

    /// The query's filters as a SQL condition on `item`, with its arguments.
    static func filterSQL(_ query: SearchQuery) -> (sql: String, values: [DatabaseValue]) {
        var conditions: [String] = []
        var values: [DatabaseValue] = []

        /// "expression IN (?, …)", binding the values; nil when there are none.
        func inList(_ expression: String, _ rawValues: [String]) -> String? {
            guard !rawValues.isEmpty else { return nil }
            values += rawValues.sorted().map(\.databaseValue)
            return "\(expression) IN (\(placeholders(rawValues.count)))"
        }

        conditions.append(inList("item.status", query.statuses.map(\.rawValue)) ?? "item.status <> 'trashed'")
        // One "kind" facet: an item matches if either its content or its capture kind is chosen.
        let kindClauses = [
            inList("item.semanticKind", query.kinds.map(\.rawValue)),
            inList("item.kind", query.captureKinds.map(\.rawValue)),
        ].compactMap { $0 }
        if !kindClauses.isEmpty {
            conditions.append("(\(kindClauses.joined(separator: " OR ")))")
        }
        // The user's intent wins; the suggested one stands in until they pick one.
        if let clause = inList("COALESCE(item.intent, item.suggestedIntent)", query.intents.map(\.rawValue)) {
            conditions.append(clause)
        }
        if let interval = query.savedWithin {
            conditions.append("item.createdAt >= ? AND item.createdAt <= ?")
            values += [interval.start.databaseValue, interval.end.databaseValue]
        }
        if let site = query.site?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !site.isEmpty {
            conditions.append(
                "(instr(lower(COALESCE(item.siteName, '')), ?) > 0 OR instr(lower(COALESCE(item.canonicalURL, '')), ?) > 0)"
            )
            values += [site.databaseValue, site.databaseValue]
        }
        return (conditions.joined(separator: " AND "), values)
    }

    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
