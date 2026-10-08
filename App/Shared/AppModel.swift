import Foundation
import Observation
import Model
import Capture
import Library
import Intelligence
import Pipeline

/// Composition root: owns the database and wires capture → ingest → pipeline.
@MainActor
@Observable
final class AppModel {
    let repository: ItemRepository
    let store: EnvelopeStore
    private(set) var lastError: String?

    private let ingestor: Ingestor
    private let pipeline: PipelineRunner
    @ObservationIgnored private var watcher: InboxWatcher?
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(database: LibraryDatabase, store: EnvelopeStore = EnvelopeStore()) {
        self.store = store
        repository = ItemRepository(database: database)
        ingestor = Ingestor(store: store, database: database, itemsDirectory: AppGroup.itemsURL)
        pipeline = PipelineRunner(database: database, understander: IntelligenceRouter.makeUnderstander())
    }

    static func live() -> AppModel {
        do {
            return AppModel(database: try LibraryDatabase.onDisk(at: AppGroup.databaseURL))
        } catch {
            // Keep the UI usable and surface the problem instead of crashing at launch.
            // swiftlint:disable:next force_try
            let model = AppModel(database: try! LibraryDatabase.inMemory())
            model.lastError = error.localizedDescription
            return model
        }
    }

    func start() async {
        if watcher == nil {
            let watcher = InboxWatcher(url: store.inboxURL) { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.processInbox() }
            }
            watcher.start()
            self.watcher = watcher
        }
        await processInbox()
    }

    /// Ingests new captures, then runs enrichment. Coalesces overlapping calls.
    func processInbox() async {
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        repeat {
            needsAnotherPass = false
            do {
                try await ingestor.ingestPending()
                await pipeline.drain()
            } catch {
                lastError = error.localizedDescription
            }
        } while needsAnotherPass
    }
}
