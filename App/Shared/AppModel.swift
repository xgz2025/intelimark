import Foundation
import Observation
import Model
import Capture
import Library
import Intelligence
import Pipeline
import Search
import Features

/// Composition root: owns the database and wires capture → ingest → pipeline.
@MainActor
@Observable
final class AppModel {
    let repository: ItemRepository
    let search: HybridSearch
    let store: EnvelopeStore
    @ObservationIgnored private(set) var services: LibraryServices!
    private(set) var lastError: String?

    private let ingestor: Ingestor
    private let pipeline: PipelineRunner
    @ObservationIgnored private var watcher: InboxWatcher?
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(database: LibraryDatabase, store: EnvelopeStore = EnvelopeStore()) {
        self.store = store
        repository = ItemRepository(database: database)
        let embedder = ContextualEmbeddingProvider()
        search = HybridSearch(repository: repository, embedder: embedder)
        ingestor = Ingestor(store: store, database: database, itemsDirectory: AppGroup.itemsURL)
        pipeline = PipelineRunner(
            database: database,
            itemsDirectory: AppGroup.itemsURL,
            understander: IntelligenceRouter.makeUnderstander(),
            embedder: embedder,
            briefWriter: IntelligenceRouter.makeBriefWriter()
        )
        services = LibraryServices(database: database, search: search) { [weak self] in
            await self?.processInbox()
        }
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
        if IntelligenceStatus.current == .available {
            // Items understood without the model (or with an older prompt) get another pass.
            await pipeline.requeueStaleUnderstanding()
            await pipeline.requeueStaleBriefs()
        }
        // Items saved before the embedding model was on the device, or embedded by
        // a model an OS update replaced, get vectors for semantic search.
        await pipeline.requeueStaleEmbeddings()
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
                // Suggested groups and Briefs follow the items they're built from.
                await pipeline.maintainGroups()
            } catch {
                lastError = error.localizedDescription
            }
        } while needsAnotherPass
    }
}
