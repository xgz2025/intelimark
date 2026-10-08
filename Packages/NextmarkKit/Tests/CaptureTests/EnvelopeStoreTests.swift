import Foundation
import Testing
import Model
@testable import Capture

struct EnvelopeStoreTests {
    let store: EnvelopeStore

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "EnvelopeStoreTests-\(UUID().uuidString)")
        store = EnvelopeStore(inboxURL: root.appending(path: "Inbox"))
    }

    @Test func committedEnvelopesAreListedOldestFirst() throws {
        let newer = CaptureEnvelope(id: ULID(date: Date(timeIntervalSince1970: 2_000)), device: "d", surface: .shareSheet, text: "b")
        let older = CaptureEnvelope(id: ULID(date: Date(timeIntervalSince1970: 1_000)), device: "d", surface: .shareSheet, text: "a")
        try store.commit(newer)
        try store.commit(older)

        let captures = try store.committedCaptures()
        #expect(captures.map(\.envelope) == [older, newer])
    }

    @Test func uncommittedCapturesAreInvisibleAndCollectedAfterADay() throws {
        let now = Date()
        let abandoned = ULID(date: now.addingTimeInterval(-2 * 24 * 60 * 60))
        let inProgress = ULID(date: now.addingTimeInterval(-60))
        try store.makePayloadDirectory(for: abandoned)
        try store.makePayloadDirectory(for: inProgress)

        #expect(try store.committedCaptures().isEmpty)
        #expect(try store.collectGarbage(now: now) == 1)
        #expect(FileManager.default.fileExists(atPath: store.directory(for: inProgress).path(percentEncoded: false)))
    }

    @Test func discardRemovesTheCapture() throws {
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "x")
        try store.commit(envelope)
        try store.discard(envelope.id)
        #expect(try store.committedCaptures().isEmpty)
    }

    @Test func pageCaptureParsesPreprocessingResults() {
        let page = PageCapture(dictionary: [
            "url": "https://example.com/p",
            "title": "  A page  ",
            "lang": "en",
            "canonical": "https://example.com/canonical",
            "jsonLD": ["{}"],
            "selection": ["exact": "selected words", "prefix": "before", "suffix": ""],
        ])
        #expect(page.url == URL(string: "https://example.com/p"))
        #expect(page.title == "A page")
        #expect(page.selection == TextQuote(exact: "selected words", prefix: "before", suffix: nil))
        #expect(page.jsonLD == ["{}"])
    }
}
