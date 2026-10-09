import Foundation
import Testing
import GRDB
import Model
import Library
import Intelligence
@testable import Search

/// A tiny "meaning" model: words map to concepts, and every text shares a small
/// constant component, like the baseline similarity of real sentence vectors.
struct ConceptEmbedder: EmbeddingProvider {
    static let concepts: [[String]] = [
        ["ramen", "noodle", "soba", "udon"],
        ["chair", "desk", "office"],
        ["concert", "music", "gig"],
    ]

    func embed(_ text: String) async throws -> TextEmbedding {
        TextEmbedding(modelID: "concepts#1", vector: Self.vector(for: text))
    }

    func isCurrent(_ modelID: String) async -> Bool { modelID == "concepts#1" }

    static func vector(for text: String) -> [Float] {
        let lowered = text.lowercased()
        let hits = concepts.map { words in Float(words.filter { lowered.contains($0) }.count) }
        return VectorMath.normalized(hits + [0.3])
    }
}

struct FailingEmbedder: EmbeddingProvider {
    func embed(_ text: String) async throws -> TextEmbedding { throw EmbeddingError.assetsUnavailable }
    func isCurrent(_ modelID: String) async -> Bool { true }
}

struct HybridSearchTests {
    let database: LibraryDatabase
    var repository: ItemRepository { ItemRepository(database: database) }
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    init() throws {
        database = try LibraryDatabase.inMemory()
    }

    func search(_ embedder: (any EmbeddingProvider)? = ConceptEmbedder()) -> HybridSearch {
        HybridSearch(repository: repository, embedder: embedder)
    }

    /// Inserts an item and embeds its title, as the pipeline would.
    @discardableResult
    func insert(_ title: String, daysAgo: Double = 0, _ configure: (inout ItemRecord) -> Void = { _ in }) async throws -> String {
        var item = ItemRecord(envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, title: title), now: now)
        item.createdAt = now.addingTimeInterval(-daysAgo * 86_400)
        configure(&item)
        let record = item
        try await database.writer.write { db in try record.insert(db) }
        let embedding = try await ConceptEmbedder().embed(title)
        try await repository.saveEmbedding(embedding.vector, modelID: embedding.modelID, forItem: record.id)
        return record.id
    }

    @Test func findsItemsByMeaning() async throws {
        let ramen = try await insert("Ichiran ramen shop")
        try await insert("Aeron office chair")
        try await insert("Autumn concert tickets")

        let results = try await search().search(SearchQuery(text: "noodles"), now: now)
        #expect(results.map(\.id) == [ramen])
    }

    @Test func itemsFoundBothWaysRankFirst() async throws {
        let desk = try await insert("Standing desk")
        let chair = try await insert("Aeron chair")
        try await insert("Ramen guide")

        let results = try await search().search(SearchQuery(text: "chair"), now: now)
        #expect(results.map(\.id) == [chair, desk])
    }

    @Test func fallsBackToKeywordsWithoutAModel() async throws {
        let ramen = try await insert("Ramen guide")
        try await insert("Soba list")
        for embedder in [FailingEmbedder() as (any EmbeddingProvider)?, nil] {
            let results = try await search(embedder).search(SearchQuery(text: "ramen"), now: now)
            #expect(results.map(\.id) == [ramen])
        }
    }

    @Test func filtersApplyToMeaningMatches() async throws {
        try await insert("Ramen shop") { $0.semanticKind = .place }
        let bowl = try await insert("Udon bowl") { $0.semanticKind = .product }

        let results = try await search().search(SearchQuery(text: "noodles", kinds: [.product]), now: now)
        #expect(results.map(\.id) == [bowl])
    }

    @Test func emptyTextListsFilteredItemsNewestFirst() async throws {
        let older = try await insert("Concert", daysAgo: 5) { $0.intent = .go }
        let newer = try await insert("Gig", daysAgo: 1) { $0.intent = .go }
        try await insert("Chair", daysAgo: 0) { $0.intent = .buy }

        let results = try await search().search(SearchQuery(intents: [.go]), now: now)
        #expect(results.map(\.id) == [newer, older])
    }

    @Test func keepsOnlyVectorsNearTheBestMatch() {
        var options = HybridSearch.Options()
        options.minimumSimilarity = 0.5
        options.similarityBand = 0.1
        let candidates = [
            StoredVector(itemID: "far", vector: [0, 1]),
            StoredVector(itemID: "best", vector: [1, 0]),
            StoredVector(itemID: "close", vector: [0.95, 0.31]),
            StoredVector(itemID: "within-floor-outside-band", vector: [0.7, 0.71]),
            StoredVector(itemID: "other-model", vector: [1, 0, 0]),
        ]
        #expect(HybridSearch.nearest(to: [1, 0], among: candidates, options: options) == ["best", "close"])
    }
}

struct SearchRankingTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    func item(_ id: String, daysAgo: Double = 0, status: ItemStatus = .active, intent: Intent? = nil) -> ItemRecord {
        var item = ItemRecord(envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, title: id), now: now)
        item.id = id
        item.createdAt = now.addingTimeInterval(-daysAgo * 86_400)
        item.status = status
        item.intent = intent
        return item
    }

    @Test func doneAndFadedItemsSink() {
        let items = [item("done", status: .done), item("faded", status: .faded), item("open")]
        let base = ["done": 0.02, "faded": 0.02, "open": 0.016]
        #expect(SearchRanking().rank(items, baseScores: base, now: now).map(\.id) == ["open", "done", "faded"])
    }

    @Test func recencyBreaksCloseCallsButNotClearOnes() {
        let ranking = SearchRanking()
        let close = ranking.rank(
            [item("old", daysAgo: 365), item("new")],
            baseScores: ["old": 0.0160, "new": 0.0155], now: now
        )
        #expect(close.map(\.id) == ["new", "old"])

        let clear = ranking.rank(
            [item("old", daysAgo: 365), item("new")],
            baseScores: ["old": 1 / 61.0, "new": 1 / 70.0], now: now
        )
        #expect(clear.map(\.id) == ["old", "new"])
    }

    @Test func anIntentNudgesTies() {
        let items = [item("plain"), item("intended", intent: .tryIt)]
        #expect(SearchRanking().rank(items, baseScores: ["plain": 0.016, "intended": 0.016], now: now).map(\.id) == ["intended", "plain"])
    }
}
