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
import Model
import Library
import Intelligence

/// Keyword and meaning search over the library (Docs/architecture.md §9, PRD F1/F2).
///
/// Full-text (FTS5, BM25) and semantic (cosine over item vectors) results are merged
/// with Reciprocal Rank Fusion, then nudged by recency, intent and status. Both halves
/// apply the same filters. Without an embedding model (assets not downloaded yet, an
/// unsupported script) search quietly falls back to keywords alone.
public struct HybridSearch: Sendable {
    public struct Options: Sendable {
        public var lexicalLimit = 100
        public var semanticLimit = 30
        /// Vectors below this cosine similarity never count as a match…
        public var minimumSimilarity: Float = 0.5
        /// …nor those further than this from the best match. Mean-pooled vectors of
        /// unrelated texts are still fairly similar, so the band does most of the work.
        /// Both are tuned on the eval set.
        public var similarityBand: Float = 0.12
        public var ranking = SearchRanking()

        public init() {}
    }

    private let repository: ItemRepository
    private let embedder: (any EmbeddingProvider)?
    public var options: Options

    public init(repository: ItemRepository, embedder: (any EmbeddingProvider)?, options: Options = Options()) {
        self.repository = repository
        self.embedder = embedder
        self.options = options
    }

    /// Best matches first. With no text, the newest items that pass the filters.
    public func search(_ query: SearchQuery, limit: Int = 50, now: Date = Date()) async throws -> [ItemRecord] {
        guard !query.trimmedText.isEmpty else {
            return try await repository.items(ids: repository.recentMatches(for: query, limit: limit))
        }
        let lexical = try await repository.lexicalMatches(for: query, limit: options.lexicalLimit)
        let semantic = await semanticMatches(for: query)
        let fused = RankFusion.scores([lexical, semantic])
        let items = try await repository.items(ids: fused.order)
        return Array(options.ranking.rank(items, baseScores: fused.scores, now: now).prefix(limit))
    }

    /// Item IDs whose vectors are near the query's, nearest first.
    func semanticMatches(for query: SearchQuery) async -> [String] {
        guard let embedder else { return [] }
        do {
            let embedding = try await embedder.embed(query.trimmedText)
            let candidates = try await repository.vectors(modelID: embedding.modelID, matching: query)
            return Self.nearest(to: embedding.vector, among: candidates, options: options)
        } catch {
            return []   // e.g. model assets not on the device yet: keyword results only
        }
    }

    struct Scored {
        var itemID: String
        var similarity: Float
    }

    static func nearest(to vector: [Float], among candidates: [StoredVector], options: Options) -> [String] {
        let scored = candidates
            .filter { $0.vector.count == vector.count }
            .map { Scored(itemID: $0.itemID, similarity: VectorMath.cosineSimilarity(vector, $0.vector)) }
            .filter { $0.similarity >= options.minimumSimilarity }
            .sorted { $0.similarity > $1.similarity }
        guard let best = scored.first?.similarity else { return [] }
        return scored
            .prefix { $0.similarity >= best - options.similarityBand }
            .prefix(options.semanticLimit)
            .map { $0.itemID }
    }
}

/// Final ordering on top of the fused score: newer items, items with an intent and
/// pinned items rise a little; done and faded items sink (Docs/architecture.md §9).
/// The boosts are small next to the fused score (1/61 for a top hit in one list),
/// so they reorder close calls rather than override relevance.
public struct SearchRanking: Sendable {
    /// Added for a brand-new item, halving every `recencyHalfLife`.
    public var recencyWeight = 0.002
    public var recencyHalfLife: TimeInterval = 30 * 86_400
    public var intentBonus = 0.0005
    public var pinnedBonus = 0.0005
    /// Multiplier for done and faded items.
    public var settledFactor = 0.7

    public init() {}

    public func score(base: Double, for item: ItemRecord, now: Date) -> Double {
        let age = max(0, now.timeIntervalSince(item.createdAt))
        var score = base + recencyWeight * pow(0.5, age / recencyHalfLife)
        if item.intent != nil { score += intentBonus }
        if item.pinned { score += pinnedBonus }
        if item.status == .done || item.status == .faded { score *= settledFactor }
        return score
    }

    /// Highest score first; ties keep the input order.
    public func rank(_ items: [ItemRecord], baseScores: [String: Double], now: Date) -> [ItemRecord] {
        let scored = items.enumerated().map { offset, item in
            (item: item, score: score(base: baseScores[item.id] ?? 0, for: item, now: now), offset: offset)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map { $0.item }
    }
}
