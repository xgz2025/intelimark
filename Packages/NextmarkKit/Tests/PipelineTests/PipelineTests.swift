import Foundation
import Testing
import Model
import Capture
import Library
import Intelligence
@testable import Pipeline

struct PipelineTests {
    @Test func captureFlowsThroughExtractAndUnderstand() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PipelineTests-\(UUID().uuidString)")
        let database = try LibraryDatabase.inMemory()
        let store = EnvelopeStore(inboxURL: root.appending(path: "Inbox"))
        let ingestor = Ingestor(store: store, database: database, itemsDirectory: root.appending(path: "Items"))

        let envelope = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet,
            url: URL(string: "https://www.youtube.com/watch?v=abc"), title: "Knife skills for beginners"
        )
        try store.commit(envelope)
        let now = Date()
        try await ingestor.ingestPending(now: now)

        let runner = PipelineRunner(database: database, understander: HeuristicUnderstander())
        let ran = await runner.drain(now: now)
        #expect(ran == 3)   // extract → understand → embed (placeholder)

        let item = try #require(try await ItemRepository(database: database).item(id: envelope.id.rawValue))
        #expect(item.aiTitle == "Knife skills for beginners")
        #expect(item.semanticKind == .video)
        #expect(item.derivedVersion == PipelineRunner.understandVersion)
        #expect(try await JobQueue(database: database).count() == 0)
    }

    @Test func failingJobsAreRetriedWithBackoff() async throws {
        struct Failing: ItemUnderstander {
            func understand(_ input: UnderstandingInput) async throws -> Understanding {
                throw CancellationError()
            }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "PipelineTests-\(UUID().uuidString)")
        let database = try LibraryDatabase.inMemory()
        let store = EnvelopeStore(inboxURL: root.appending(path: "Inbox"))
        let now = Date()
        try store.commit(CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "a note"))
        try await Ingestor(store: store, database: database, itemsDirectory: root.appending(path: "Items"))
            .ingestPending(now: now)

        let runner = PipelineRunner(database: database, understander: Failing())
        #expect(await runner.drain(now: now) == 2)   // extract succeeds, understand fails

        let queue = JobQueue(database: database)
        #expect(try await queue.count() == 1)
        #expect(try await queue.next(now: now) == nil)                          // backed off…
        #expect(try await queue.next(now: now.addingTimeInterval(61)) != nil)   // …for one minute
    }
}
