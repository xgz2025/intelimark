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
import Network
import Observation
import Model
import Capture
import Library
import Intelligence
import Pipeline
import Search
import Features
import Moments
import Sync
import Integrations
import Store
import UserNotifications
import WidgetKit

/// Composition root: owns the database and wires capture → ingest → pipeline.
@MainActor
@Observable
final class AppModel {
    let repository: ItemRepository
    let search: HybridSearch
    let store: EnvelopeStore
    @ObservationIgnored private(set) var services: LibraryServices!
    /// Where notification taps lead; RootView follows it.
    let navigator = AppNavigator()
    /// Nextmark Pro (PRD P4): Moments, Briefs and unlimited smart groups.
    let pro = ProAccess()
    private(set) var lastError: String?
    /// The library couldn't be opened. Captures then stay in the Inbox untouched (an
    /// in-memory library would lose them) and the app says so.
    private(set) var startupError: String?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var widgetFeed: Task<Void, Never>?

    private let ingestor: Ingestor
    private let pipeline: PipelineRunner
    private let moments: MomentsEngine
    @ObservationIgnored private var cloudSync: CloudSync?
    /// Screenshot Rescue (PRD C9), on iPhone and iPad.
    @ObservationIgnored private(set) var rescue: RescueController?
    #if os(iOS)
    @ObservationIgnored private let continuedTasks = ContinuedTaskRunner()
    #endif
    @ObservationIgnored private var notificationRouter: NotificationRouter?
    @ObservationIgnored private var watcher: InboxWatcher?
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false
    /// Wakes the pipeline when a postponed job (a fetch that failed offline) is due.
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var wasOnline: Bool?
    @ObservationIgnored private var powerObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastPowerBudget = PowerBudget.full
    /// Whether Apple Intelligence was ready last time we looked, to catch it becoming
    /// ready (its model finished downloading, it was turned on) while the app runs.
    @ObservationIgnored private var wasIntelligenceAvailable = false

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
        moments = MomentsEngine(database: database, scheduler: UserNotificationScheduler())
        services = LibraryServices(
            database: database,
            search: search,
            itemsDirectory: AppGroup.itemsURL,
            refresh: { [weak self] in
                await self?.updateSync()
                await self?.processInbox()
            },
            syncNow: { [weak self] in
                await self?.syncNow()
            }
        )
        cloudSync = CloudSync(store: SyncStore(database: database, itemsDirectory: AppGroup.itemsURL)) { [weak self] result in
            await self?.didSync(result)
        }
        #if os(iOS)
        let importer = ScreenshotImporter(database: database, itemsDirectory: AppGroup.itemsURL, device: DeviceIdentity.current())
        let rescue = RescueController(rescue: ScreenshotRescue(source: PhotosScreenshotSource(), importer: importer)) { [weak self] in
            await self?.processInbox()
        }
        rescue.runner = continuedTasks
        self.rescue = rescue
        #endif
        // Set before launch finishes, so a tap that launched the app is delivered.
        UserNotificationScheduler.registerCategories()
        let router = NotificationRouter { [weak self] response in
            await self?.handle(response)
        }
        UNUserNotificationCenter.current().delegate = router
        notificationRouter = router
        // Buying or losing Pro changes which Moments are scheduled and whether Briefs are written.
        pro.onChange = { [weak self] _ in
            guard let self else { return }
            Task { await self.processInbox() }
        }
    }

    /// A notification answer: record it, carry it out, and go where Open leads.
    func handle(_ response: MomentResponse) async {
        if let destination = try? await moments.handle(response) {
            navigator.open(destination)
        }
        await rescheduleMoments()
    }

    /// Starts or stops iCloud sync to match Settings (PRD P1, P2).
    func updateSync() async {
        // An in-memory library must never sync: it would look like everything was deleted.
        guard startupError == nil else { return }
        await cloudSync?.update(enabled: SyncSettings.isEnabled(), originals: SyncSettings.syncsOriginals())
    }

    func syncNow() async {
        await cloudSync?.syncNow()
    }

    /// Another device's changes arrived: give new and changed items vectors here, and
    /// understand them with the on-device model if their sender couldn't (PRD U6).
    func didSync(_ result: SyncApplyResult) async {
        await pipeline.enqueueSyncedItems(
            Array(result.changedItemIDs), canUnderstand: IntelligenceStatus.current == .available
        )
        await processInbox()
    }

    /// Plans notifications from the library's dates and the user's settings (PRD M1, M2, M5).
    func rescheduleMoments() async {
        var settings = MomentSettings(defaults: .standard)
        settings.includesTimeMoments = pro.isPro
        _ = try? await moments.reschedule(settings: settings)
    }

    static func live() -> AppModel {
        do {
            LibraryDatabase.moveLegacyDatabase(from: AppGroup.legacyDatabaseURL, to: LibraryDatabase.defaultURL)
            return AppModel(database: try LibraryDatabase.onDisk(at: LibraryDatabase.defaultURL))
        } catch {
            // Keep the UI usable and surface the problem instead of crashing at launch.
            // swiftlint:disable:next force_try
            let model = AppModel(database: try! LibraryDatabase.inMemory())
            model.startupError = error.localizedDescription
            // Rescued screenshots would only reach the throwaway library, and "Clean Up
            // Photos" could then delete originals the real one never got.
            model.rescue = nil
            return model
        }
    }

    /// Runs once, at launch: capture, sync and Moments work with no window open (the
    /// Mac's menu bar, hotkey and Services).
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await pro.start()
        guard startupError == nil else { return }
        // Items in the Trash longer than 30 days are deleted for good.
        _ = try? await repository.purgeTrash(itemsDirectory: AppGroup.itemsURL)
        await updateSync()
        await requeueForModelIfReady()
        // Items saved before the embedding model was on the device, or embedded by
        // a model an OS update replaced, get vectors for semantic search.
        await pipeline.requeueStaleEmbeddings()
        // Links saved offline whose page never arrived get another try.
        await pipeline.requeueMissingPages()
        watchNetwork()
        watchPower()
        feedWidget()
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

    /// Keeps the Next Actions widget's snapshot current: the widget never opens the
    /// database, it reads this file (Docs/architecture.md §2).
    private func feedWidget() {
        guard widgetFeed == nil else { return }
        let actions = services.actions
        widgetFeed = Task {
            var last: [WidgetSnapshot.Action]?
            do {
                for try await open in actions.nextActions() {
                    let snapshot = WidgetSnapshot(generatedAt: Date(), actions: open.prefix(8).map { context in
                        WidgetSnapshot.Action(
                            id: context.id,
                            title: context.action.title,
                            groupTitle: context.groupTitle ?? context.itemTitle,
                            dueDate: context.action.dueAt
                        )
                    })
                    guard snapshot.actions != last else { continue }
                    last = snapshot.actions
                    try? snapshot.save()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                // The observation ended; the widget keeps its last snapshot.
            }
        }
    }

    /// Back in the foreground: new screenshots (once a rescue has run), new captures.
    func becameActive() async {
        // A subscription can lapse while the app runs; StoreKit sends no update for that.
        await pro.refresh()
        guard startupError == nil else { return }
        await requeueForModelIfReady()
        await rescue?.importNew()
        await processInbox()
    }

    /// Items understood without the model (or with an older prompt), and Briefs written
    /// without it, get another pass once the model is ready: at launch, or when it
    /// becomes ready while the app runs.
    private func requeueForModelIfReady() async {
        let isAvailable = IntelligenceStatus.current == .available
        defer { wasIntelligenceAvailable = isAvailable }
        guard isAvailable, !wasIntelligenceAvailable else { return }
        await pipeline.requeueStaleUnderstanding()
        await pipeline.requeueStaleBriefs()
    }

    /// Ingests new captures, then runs enrichment. Coalesces overlapping calls.
    func processInbox() async {
        guard startupError == nil else { return }
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        // Its own task: a caller being cancelled (an expiring background task) mustn't
        // cut a pass short and drop the passes folded into it.
        let pass = Task { await self.runPasses() }
        await pass.value
        isProcessing = false
        await scheduleWake()
    }

    private func runPasses() async {
        repeat {
            needsAnotherPass = false
            // Each stage runs even if the one before it failed.
            do {
                try await ingestor.ingestPending()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            // What's still waiting couldn't be added; the Inbox says so.
            let waiting = ingestor.waitingCount()
            CaptureStatus.shared.stuckCount = waiting
            CaptureStatus.shared.reason = waiting > 0 ? lastError : nil
            // A full batch means more is waiting (e.g. a screenshot rescue): go round again,
            // unless the device is hot or in Low Power Mode, when a few jobs at a time will do.
            let budget = PowerBudget.current
            if budget.batchSize > 0, await pipeline.drain(limit: budget.batchSize) == budget.batchSize, budget == .full {
                needsAnotherPass = true
            }
            // Suggested groups and Briefs follow the items they're built from.
            await pipeline.maintainGroups(writesBriefs: pro.isPro)
            await rescheduleMoments()
        } while needsAnotherPass
    }

    /// Runs the pipeline again when the next postponed job is due, while the app runs
    /// (the Mac app can run for weeks).
    private func scheduleWake() async {
        wake?.cancel()
        guard let due = await pipeline.nextDueDate() else { return }
        // At least a few seconds out, so a job due now can't make this spin; minutes
        // out while the device is hot or in Low Power Mode.
        let delay = min(max(due.timeIntervalSinceNow, PowerBudget.current.minimumWakeDelay), 6 * 60 * 60)
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.processInbox()
        }
    }

    /// Cooler, or out of Low Power Mode: catch up on what waited.
    private func watchPower() {
        guard powerObservers.isEmpty else { return }
        lastPowerBudget = PowerBudget.current
        let names = [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange]
        powerObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.powerChanged() }
            }
        }
    }

    private func powerChanged() async {
        let budget = PowerBudget.current
        defer { lastPowerBudget = budget }
        guard budget == .full, lastPowerBudget != .full else { return }
        await processInbox()
    }

    /// Back online: links saved meanwhile get their pages now instead of after backoff.
    private func watchNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            Task { @MainActor in await self.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.nextmark.app.network"))
        pathMonitor = monitor
    }

    private func networkChanged(online: Bool) async {
        defer { wasOnline = online }
        guard online, wasOnline == false else { return }
        await pipeline.retryFetchesNow()
        await pipeline.requeueMissingPages()
        await processInbox()
    }
}
