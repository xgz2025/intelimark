import Foundation
import Testing
import GRDB
import Model
@testable import Library

struct SearchStorageTests {
    let database: LibraryDatabase
    var repository: ItemRepository { ItemRepository(database: database) }
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    init() throws {
        database = try LibraryDatabase.inMemory()
    }

    /// Inserts an item directly (no job), saved `daysAgo` days before `now`.
    @discardableResult
    func insert(title: String, daysAgo: Double = 0, _ configure: (inout ItemRecord) -> Void = { _ in }) async throws -> String {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, title: title),
            now: now
        )
        item.createdAt = now.addingTimeInterval(-daysAgo * 86_400)
        configure(&item)
        let record = item
        try await database.writer.write { db in try record.insert(db) }
        return record.id
    }

    @Test func filtersCombine() async throws {
        let chair = try await insert(title: "Aeron chair", daysAgo: 2) {
            $0.semanticKind = .product
            $0.siteName = "Herman Miller"
            $0.canonicalURL = "https://store.hermanmiller.com/aeron"
            $0.intent = .buy
        }
        let receipt = try await insert(title: "Chair receipt", daysAgo: 40) {
            $0.kind = .image
            $0.semanticKind = .receipt
            $0.suggestedIntent = .reference
            $0.status = .done
        }
        let trashed = try await insert(title: "Old chair article", daysAgo: 1) {
            $0.semanticKind = .article
            $0.status = .trashed
        }

        func matches(_ query: SearchQuery) async throws -> Set<String> {
            let ids = try await repository.recentMatches(for: query)
            return Set(ids)
        }
        #expect(try await matches(SearchQuery()) == [chair, receipt])
        #expect(try await matches(SearchQuery(kinds: [.product], captureKinds: [.image])) == [chair, receipt])
        #expect(try await matches(SearchQuery(kinds: [.product])) == [chair])
        #expect(try await matches(SearchQuery(intents: [.reference])) == [receipt])   // suggested intent counts
        #expect(try await matches(SearchQuery(statuses: [.done, .trashed])) == [receipt, trashed])
        #expect(try await matches(SearchQuery(savedWithin: DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now))) == [chair])
        #expect(try await matches(SearchQuery(site: "hermanmiller.com")) == [chair])
        #expect(try await matches(SearchQuery(site: "HERMAN miller")) == [chair])
        #expect(try await matches(SearchQuery(kinds: [.product], intents: [.reference])).isEmpty)
    }

    @Test func recentMatchesAreNewestFirst() async throws {
        let old = try await insert(title: "Old", daysAgo: 10)
        let new = try await insert(title: "New", daysAgo: 1)
        #expect(try await repository.recentMatches(for: SearchQuery()) == [new, old])
    }

    @Test func lexicalMatchesApplyFilters() async throws {
        let open = try await insert(title: "Ramen guide")
        try await insert(title: "Ramen list") { $0.status = .trashed }
        try await insert(title: "Ramen photo") { $0.kind = .image }
        #expect(try await repository.lexicalMatches(for: SearchQuery(text: "ram", captureKinds: [.note])) == [open])
        #expect(try await repository.lexicalMatches(for: SearchQuery(text: "  ")).isEmpty)
    }

    @Test func embeddingsAreReplacedAndFiltered() async throws {
        let first = try await insert(title: "First")
        let second = try await insert(title: "Second") { $0.status = .trashed }
        try await repository.saveEmbedding([1, 0], modelID: "old#1", forItem: first)
        try await repository.saveEmbedding([0, 1], modelID: "new#1", forItem: first)
        try await repository.saveEmbedding([1, 1], modelID: "new#1", forItem: second)
        try await repository.saveEmbedding([1, 1], modelID: "new#1", forItem: "missing")   // ignored

        #expect(try await repository.embedding(forItem: first)?.modelID == "new#1")
        #expect(try await repository.embedding(forItem: first)?.floats == [0, 1])
        #expect(try await repository.vectors(modelID: "new#1", matching: SearchQuery()) == [StoredVector(itemID: first, vector: [0, 1])])
        #expect(try await repository.vectors(modelID: "old#1", matching: SearchQuery()).isEmpty)
        #expect(try await repository.embeddingModelIDs() == ["new#1"])
    }

    @Test func findsItemsNeedingEmbedding() async throws {
        let embedded = try await insert(title: "Embedded", daysAgo: 3)
        let stale = try await insert(title: "Stale", daysAgo: 2)
        let missing = try await insert(title: "Missing", daysAgo: 1)
        try await insert(title: "Trashed") { $0.status = .trashed }
        try await repository.saveEmbedding([1], modelID: "current#2", forItem: embedded)
        try await repository.saveEmbedding([1], modelID: "current#1", forItem: stale)

        #expect(try await repository.itemIDsNeedingEmbedding() == [missing])
        #expect(try await repository.itemIDsNeedingEmbedding(staleModelIDs: ["current#1"]) == [missing, stale])

        try await JobQueue(database: database).enqueue(.embed, itemID: missing, notBefore: now)
        #expect(try await repository.itemIDsNeedingEmbedding(staleModelIDs: ["current#1"]) == [stale])
    }

    @Test func vectorsRoundTripThroughBlobs() {
        let vector: [Float] = [0.25, -1.5, 3, .leastNonzeroMagnitude]
        #expect(VectorBlob.decode(VectorBlob.encode(vector)) == vector)
        #expect(VectorBlob.encode(vector).count == 16)
        #expect(VectorBlob.decode(Data()).isEmpty)
    }

    @Test func itemsKeepTheRequestedOrder() async throws {
        let a = try await insert(title: "A")
        let b = try await insert(title: "B")
        #expect(try await repository.items(ids: [b, "gone", a]).map(\.id) == [b, a])
    }
}
