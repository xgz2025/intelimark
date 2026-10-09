import Foundation
import Testing
import Model
import Capture
import Library
import Extraction
import Intelligence
@testable import Pipeline

/// Serves one canned response for every URL, or throws.
struct StubFetcher: PageFetcher {
    let respond: @Sendable (URL) throws -> FetchedResource

    static func html(_ html: String, status: Int = 200) -> StubFetcher {
        StubFetcher { url in
            FetchedResource(data: Data(html.utf8), mimeType: "text/html", textEncodingName: "utf-8", finalURL: url, statusCode: status)
        }
    }

    func fetch(_ url: URL) async throws -> FetchedResource { try respond(url) }
}

struct PipelineHarness {
    let root = FileManager.default.temporaryDirectory.appending(path: "PipelineTests-\(UUID().uuidString)")
    let database: LibraryDatabase
    let store: EnvelopeStore

    init() throws {
        database = try LibraryDatabase.inMemory()
        store = EnvelopeStore(inboxURL: root.appending(path: "Inbox"))
    }

    var itemsDirectory: URL { root.appending(path: "Items") }
    var repository: ItemRepository { ItemRepository(database: database) }
    var queue: JobQueue { JobQueue(database: database) }

    func capture(_ envelope: CaptureEnvelope, now: Date) async throws {
        try store.commit(envelope)
        try await Ingestor(store: store, database: database, itemsDirectory: itemsDirectory).ingestPending(now: now)
    }

    func runner(
        fetcher: any PageFetcher,
        understander: any ItemUnderstander = HeuristicUnderstander(),
        embedder: (any EmbeddingProvider)? = nil
    ) -> PipelineRunner {
        PipelineRunner(
            database: database,
            itemsDirectory: itemsDirectory,
            extractor: ItemExtractor(fetcher: fetcher, imageAnalyzer: nil),
            understander: understander,
            embedder: embedder
        )
    }
}

struct PipelineTests {
    static let productPage = """
        <html lang="en"><head>
        <meta property="og:title" content="Aeron Chair"><meta property="og:site_name" content="Herman Miller">
        <script type="application/ld+json">{"@type":"Product","name":"Aeron Chair","offers":{"price":1395,"priceCurrency":"USD"}}</script>
        </head><body><nav>Menu</nav><article><p>Twelve-year warranty.</p></article></body></html>
        """

    @Test func captureFlowsThroughExtractAndUnderstand() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet,
            url: URL(string: "https://www.youtube.com/watch?v=abc"), title: "Knife skills for beginners"
        )
        try await harness.capture(envelope, now: now)

        let ran = await harness.runner(fetcher: StubFetcher.html("gone", status: 404)).drain(now: now)
        #expect(ran == 3)   // extract → understand → embed (placeholder)

        let item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        #expect(item.aiTitle == "Knife skills for beginners")
        #expect(item.semanticKind == .video)
        #expect(item.extractVersion == PipelineRunner.extractVersion)
        #expect(item.derivedVersion == 0)   // heuristic results are provisional
        #expect(try await harness.queue.count() == 0)
    }

    @Test func extractedFactsAreStoredAndSearchable() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://store.example.com/aeron"), userIntent: .buy
        )
        try await harness.capture(envelope, now: now)
        await harness.runner(fetcher: StubFetcher.html(Self.productPage)).drain(now: now)

        let item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        #expect(item.sourceTitle == "Aeron Chair")         // filled because the capture had none
        #expect(item.siteName == "Herman Miller")
        #expect(item.contentText == "Twelve-year warranty.")
        #expect(item.structuredKind == .product)
        #expect(item.typedFields?.product?.price == 1395)
        // The heuristic would call this an article; the page's own schema.org data wins.
        #expect(item.semanticKind == .product)
        #expect(item.intent == .buy)

        let results = try await harness.repository.search("warranty")
        #expect(results.map(\.id) == [envelope.id.rawValue])
    }

    static let eventPage = """
        <html><head><script type="application/ld+json">
        {"@type":"MusicEvent","name":"Autumn concert","startDate":"2026-11-21T19:30:00+09:00",
         "location":{"@type":"Place","name":"Budokan","address":"Tokyo"}}
        </script></head>
        <body><article><p>Autumn concert at Budokan. Tickets on sale until November 1, 2026.</p></article></body></html>
        """

    /// Stands in for the on-device model: a non-provisional understander.
    struct ModelStandIn: ItemUnderstander {
        func understand(_ input: UnderstandingInput) async throws -> Understanding {
            Understanding(
                title: "From the model", summary: "", semanticKind: .other, likelyIntent: .reference,
                keywords: [], producer: "stand-in", isProvisional: false
            )
        }
    }

    @Test func structuredEventFactsComeFirst() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://tickets.example.com/autumn"))
        try await harness.capture(envelope, now: now)
        await harness.runner(fetcher: StubFetcher.html(Self.eventPage)).drain(now: now)

        let item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        #expect(item.semanticKind == .event)
        let first = try #require(item.dates.first)
        #expect(first.role == .eventStart)
        #expect(first.source == .structured)
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-11-21T10:30:00Z"))
        #expect(item.places == [ItemPlace(name: "Budokan", address: "Tokyo", source: .structured)])
    }

    @Test func provisionalResultsAreRequeuedOnceTheModelIsAvailable() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "Ideas for the trip")
        try await harness.capture(envelope, now: now)
        await harness.runner(fetcher: StubFetcher.html("")).drain(now: now)

        let modelRunner = harness.runner(fetcher: StubFetcher.html(""), understander: ModelStandIn())
        #expect(await modelRunner.requeueStaleUnderstanding(now: now) == 1)
        #expect(await modelRunner.requeueStaleUnderstanding(now: now) == 0)   // already queued
        await modelRunner.drain(now: now)

        let item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        #expect(item.aiTitle == "From the model")
        #expect(item.derivedVersion == PipelineRunner.understandVersion)
        #expect(await modelRunner.requeueStaleUnderstanding(now: now) == 0)
    }

    @Test func capturedTitleIsNeverReplaced() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://store.example.com/aeron"), title: "My chair research"
        )
        try await harness.capture(envelope, now: now)
        await harness.runner(fetcher: StubFetcher.html(Self.productPage)).drain(now: now)

        let item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        #expect(item.sourceTitle == "My chair research")
    }

    @Test func offlineExtractionRetriesThenFallsThroughToUnderstand() async throws {
        let harness = try PipelineHarness()
        var now = Date()
        let envelope = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://example.com/post"), title: "Saved offline"
        )
        try await harness.capture(envelope, now: now)
        let runner = harness.runner(fetcher: StubFetcher { _ in throw URLError(.notConnectedToInternet) })

        #expect(await runner.drain(now: now) == 1)
        #expect(try await harness.queue.next(now: now) == nil)              // backed off
        #expect(try await harness.queue.next(now: now.addingTimeInterval(61))?.stage == .extract)

        // Four more failures exhaust the retries; Understand then runs on what we have.
        for _ in 0..<4 {
            now = now.addingTimeInterval(7 * 60 * 60)
            await runner.drain(now: now)
        }
        let item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        #expect(item.aiTitle == "Saved offline")
        #expect(item.extractVersion == 0)
        #expect(try await harness.queue.count() == 0)
    }

    @Test func failingJobsAreRetriedWithBackoff() async throws {
        struct Failing: ItemUnderstander {
            func understand(_ input: UnderstandingInput) async throws -> Understanding {
                throw CancellationError()
            }
        }
        let harness = try PipelineHarness()
        let now = Date()
        try await harness.capture(CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "a note"), now: now)

        let runner = harness.runner(fetcher: StubFetcher.html(""), understander: Failing())
        #expect(await runner.drain(now: now) == 2)   // extract succeeds, understand fails

        #expect(try await harness.queue.count() == 1)
        #expect(try await harness.queue.next(now: now) == nil)                          // backed off…
        #expect(try await harness.queue.next(now: now.addingTimeInterval(61)) != nil)   // …for one minute
    }

    // MARK: Embed

    /// Returns a fixed vector, or throws; `currentModelID` decides which vectors are stale.
    struct StubEmbedder: EmbeddingProvider {
        var error: EmbeddingError?
        var currentModelID = "stub#1"

        func embed(_ text: String) async throws -> TextEmbedding {
            if let error { throw error }
            return TextEmbedding(modelID: currentModelID, vector: [0.6, 0.8])
        }

        func isCurrent(_ modelID: String) async -> Bool { modelID == currentModelID }
    }

    @Test func understoodItemsAreEmbedded() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "Ideas for the trip")
        try await harness.capture(envelope, now: now)
        #expect(await harness.runner(fetcher: StubFetcher.html(""), embedder: StubEmbedder()).drain(now: now) == 3)

        let embedding = try #require(try await harness.repository.embedding(forItem: envelope.id.rawValue))
        #expect(embedding.modelID == "stub#1")
        #expect(embedding.floats == [0.6, 0.8])
        #expect(try await harness.queue.count() == 0)
    }

    @Test func missingModelAssetsAreRetriedButUnsupportedTextIsNot() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "Ideas for the trip")
        try await harness.capture(envelope, now: now)

        await harness.runner(fetcher: StubFetcher.html(""), embedder: StubEmbedder(error: .assetsUnavailable)).drain(now: now)
        #expect(try await harness.queue.next(now: now.addingTimeInterval(61))?.stage == .embed)

        await harness.runner(fetcher: StubFetcher.html(""), embedder: StubEmbedder(error: .unsupportedLanguage))
            .drain(now: now.addingTimeInterval(61))
        #expect(try await harness.queue.count() == 0)
        #expect(try await harness.repository.embedding(forItem: envelope.id.rawValue) == nil)
    }

    @Test func missingAndOutdatedVectorsAreRequeued() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "Ideas for the trip")
        try await harness.capture(envelope, now: now)
        await harness.runner(fetcher: StubFetcher.html("")).drain(now: now)   // no embedder yet

        let runner = harness.runner(fetcher: StubFetcher.html(""), embedder: StubEmbedder())
        #expect(await harness.runner(fetcher: StubFetcher.html("")).requeueStaleEmbeddings(now: now) == 0)
        #expect(await runner.requeueStaleEmbeddings(now: now) == 1)
        #expect(await runner.requeueStaleEmbeddings(now: now) == 0)    // already queued
        await runner.drain(now: now)
        #expect(await runner.requeueStaleEmbeddings(now: now) == 0)

        // An OS update replaced the model: vectors from the old one are recomputed.
        let updated = harness.runner(fetcher: StubFetcher.html(""), embedder: StubEmbedder(currentModelID: "stub#2"))
        #expect(await updated.requeueStaleEmbeddings(now: now) == 1)
        await updated.drain(now: now)
        #expect(try await harness.repository.embedding(forItem: envelope.id.rawValue)?.modelID == "stub#2")
    }

    @Test func embeddingTextPutsTheUsersWordsFirst() async throws {
        let harness = try PipelineHarness()
        let now = Date()
        let envelope = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://example.com/aeron"),
            title: "Aeron Chair", selection: TextQuote(exact: "Twelve-year warranty"), userNote: "for the new desk"
        )
        try await harness.capture(envelope, now: now)
        var item = try #require(try await harness.repository.item(id: envelope.id.rawValue))
        item.summary = "An office chair."
        item.keywords = ["chair", "office"]
        item.contentText = String(repeating: "page text ", count: 500)

        let lines = PipelineRunner.embeddingText(for: item).components(separatedBy: "\n")
        #expect(Array(lines.prefix(5)) == ["Aeron Chair", "for the new desk", "An office chair.", "Twelve-year warranty", "chair, office"])
        #expect(lines.last?.count == 1_000)
    }
}
