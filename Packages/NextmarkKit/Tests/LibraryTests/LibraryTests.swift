import Foundation
import Testing
import Model
import Capture
@testable import Library

struct LibraryTests {
    let database: LibraryDatabase
    let store: EnvelopeStore
    let ingestor: Ingestor

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LibraryTests-\(UUID().uuidString)")
        database = try LibraryDatabase.inMemory()
        store = EnvelopeStore(inboxURL: root.appending(path: "Inbox"))
        ingestor = Ingestor(store: store, database: database, itemsDirectory: root.appending(path: "Items"))
    }

    @Test func ingestsALinkWithAHighlight() async throws {
        let envelope = CaptureEnvelope(
            id: ULID(),
            device: "d",
            surface: .shareSheet,
            url: URL(string: "https://example.com/ramen"),
            title: "Best ramen in Kyoto",
            selection: TextQuote(exact: "open until midnight"),
            userIntent: .go,
            userNote: "for the trip"
        )
        try store.commit(envelope)

        let ingested = try await ingestor.ingestPending()
        #expect(ingested == [envelope.id.rawValue])
        #expect(try store.committedCaptures().isEmpty)

        let item = try #require(try await ItemRepository(database: database).item(id: envelope.id.rawValue))
        #expect(item.kind == .link)
        #expect(item.status == .inbox)
        #expect(item.intent == .go)
        #expect(item.note == "for the trip")
        #expect(item.text == "open until midnight")
        guard case .web(let fragmentURL, _)? = item.anchor else {
            Issue.record("Expected a web anchor")
            return
        }
        #expect(fragmentURL.absoluteString.hasSuffix("#:~:text=open%20until%20midnight"))
        #expect(try await JobQueue(database: database).count() == 1)
    }

    @Test func ingestionIsIdempotent() async throws {
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "a quote")
        try store.commit(envelope)
        try await ingestor.ingestPending()
        try store.commit(envelope)          // e.g. the app crashed before removing the envelope
        try await ingestor.ingestPending()
        #expect(try await JobQueue(database: database).count() == 1)
    }

    @Test func movesPayloadFilesIntoTheItemDirectory() async throws {
        let id = ULID()
        let payload = try store.makePayloadDirectory(for: id)
        try Data([0xFF, 0xD8]).write(to: payload.appending(path: "0-photo.jpg"))
        let envelope = CaptureEnvelope(
            id: id, device: "d", surface: .shareSheet,
            payloadFiles: [PayloadFile(fileName: "0-photo.jpg", contentType: "public.jpeg", byteSize: 2)]
        )
        try store.commit(envelope)
        try await ingestor.ingestPending()

        let item = try #require(try await ItemRepository(database: database).item(id: id.rawValue))
        #expect(item.kind == .image)
        let moved = ingestor.itemsDirectory.appending(path: id.rawValue).appending(path: "0-photo.jpg")
        #expect(FileManager.default.fileExists(atPath: moved.path(percentEncoded: false)))
    }

    @Test func fullTextSearchMatchesPrefixes() async throws {
        try store.commit(CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://a.example"), title: "Standing desk review"))
        try store.commit(CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://b.example"), title: "Kyoto ryokan list"))
        try await ingestor.ingestPending()

        let results = try await ItemRepository(database: database).search("ryok")
        #expect(results.map(\.sourceTitle) == ["Kyoto ryokan list"])
    }

    @Test func understandingNeverTouchesTheUserLayer() async throws {
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, text: "notes", userIntent: .read, userNote: "mine")
        try store.commit(envelope)
        try await ingestor.ingestPending()

        let repository = ItemRepository(database: database)
        let understanding = Understanding(
            title: "AI title", summary: "AI summary", semanticKind: .quote,
            likelyIntent: .reference, keywords: ["notes"], producer: "test"
        )
        try await repository.applyUnderstanding(understanding, toItem: envelope.id.rawValue, version: 3)

        let item = try #require(try await repository.item(id: envelope.id.rawValue))
        #expect(item.aiTitle == "AI title")
        #expect(item.keywords == ["notes"])
        #expect(item.derivedVersion == 3)
        #expect(item.intent == .read)
        #expect(item.note == "mine")
        #expect(item.displayTitle == "AI title")
    }
}
