import Foundation
import Testing
import GRDB
import Model
import Library
@testable import Integrations

/// Photos, faked: screenshots by ID, with what got deleted.
final class FakeScreenshots: ScreenshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private var refs: [ScreenshotRef]
    private var granted: Bool
    private(set) var deleted: [String] = []
    private(set) var loads = 0

    init(count: Int, granted: Bool = true, newest: Date) {
        refs = (0..<count).map { ScreenshotRef(id: "asset-\($0)", takenAt: newest.addingTimeInterval(-Double($0) * 86_400)) }
        self.granted = granted
    }

    func access() -> PhotosAccess { lock.withLock { granted ? .granted : .notDetermined } }

    func requestAccess() async -> PhotosAccess {
        lock.withLock { granted = true }
        return .granted
    }

    func screenshots() async -> [ScreenshotRef] { lock.withLock { refs } }

    func load(_ screenshot: ScreenshotRef) async -> ImportedScreenshot? {
        lock.withLock { loads += 1 }
        return ImportedScreenshot(assetID: screenshot.id, data: Data("png".utf8), contentType: "public.png", takenAt: screenshot.takenAt)
    }

    func delete(_ ids: [String]) async throws {
        lock.withLock {
            deleted += ids
            refs.removeAll { ids.contains($0.id) }
        }
    }

    func add(_ ref: ScreenshotRef) { lock.withLock { refs.insert(ref, at: 0) } }
}

actor ProgressLog {
    private(set) var reports: [RescueProgress] = []
    func append(_ progress: RescueProgress) { reports.append(progress) }
}

struct ScreenshotRescueTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    let database: LibraryDatabase
    let directory = FileManager.default.temporaryDirectory.appending(path: "IntegrationsTests-\(UUID().uuidString)")

    init() throws {
        database = try LibraryDatabase.inMemory()
    }

    func rescue(_ source: FakeScreenshots) -> ScreenshotRescue {
        ScreenshotRescue(
            source: source,
            importer: ScreenshotImporter(database: database, itemsDirectory: directory, device: "phone")
        )
    }

    @Test func importsEveryScreenshotInBatches() async throws {
        let photos = FakeScreenshots(count: 120, newest: now)
        let log = ProgressLog()
        let imported = try await rescue(photos).run(now: now) { await log.append($0) }

        #expect(imported == 120)
        let reports = await log.reports
        #expect(reports.map(\.done) == [0, 50, 100, 120])
        #expect(Set(reports.map(\.total)) == [120])
        let items = try await database.writer.read { db in try ItemRecord.fetchAll(db) }
        #expect(items.count == 120)
        #expect(Set(items.map(\.surface)) == [.screenshotImport])
        #expect(Set(items.map(\.kind)) == [.image])
        let jobs = try await JobQueue(database: database).count()
        #expect(jobs == 120)
    }

    @Test func recentScreenshotsGoToTheInboxAndOlderOnesDont() async throws {
        let photos = FakeScreenshots(count: 10, newest: now)      // one a day, going back
        try await rescue(photos).run(now: now)

        let items = try await database.writer.read { db in try ItemRecord.order(Column("createdAt").desc).fetchAll(db) }
        #expect(items.filter { $0.status == .inbox }.count == 8)  // taken within the last 7 days
        #expect(items.filter { $0.status == .active }.count == 2)
        let inbox = try #require(await firstValue(ItemRepository(database: database).inboxItems()))
        #expect(inbox.count == 8)
    }

    @Test func aSecondRunOnlyBringsWhatsNew() async throws {
        let photos = FakeScreenshots(count: 5, newest: now)
        let rescue = rescue(photos)
        try await rescue.run(now: now)
        photos.add(ScreenshotRef(id: "asset-new", takenAt: now))

        #expect(await rescue.pending().map(\.id) == ["asset-new"])
        #expect(try await rescue.run(now: now) == 1)
        #expect(try await rescue.run(now: now) == 0)
        #expect(photos.loads == 6)
    }

    @Test func nothingHappensWithoutAccess() async throws {
        let photos = FakeScreenshots(count: 5, granted: false, newest: now)
        let rescue = rescue(photos)
        #expect(try await rescue.run(now: now) == 0)
        #expect(await rescue.screenshotCount() == 0)
        #expect(await rescue.requestAccess() == .granted)
        #expect(await rescue.screenshotCount() == 5)
    }

    @Test func cleaningUpDeletesFromPhotosAndKeepsTheItems() async throws {
        let photos = FakeScreenshots(count: 3, newest: now)
        let rescue = rescue(photos)
        try await rescue.run(now: now)
        #expect(await rescue.inPhotosCount() == 3)

        #expect(try await rescue.cleanUpPhotos() == 3)
        #expect(Set(photos.deleted) == ["asset-0", "asset-1", "asset-2"])
        #expect(await rescue.inPhotosCount() == 0)
        let items = try await database.writer.read { db in try ItemRecord.fetchCount(db) }
        #expect(items == 3)
        // Deleted from Photos, so they're not pending again either.
        #expect(await rescue.pending().isEmpty)
    }

    @Test func importedFilesLandInTheItemsFolder() async throws {
        let photos = FakeScreenshots(count: 1, newest: now)
        try await rescue(photos).run(now: now)
        let item = try #require(try await database.writer.read { db in try ItemRecord.fetchOne(db) })
        let attachment = try #require(try await ItemRepository(database: database).attachments(forItem: item.id).first)
        #expect(attachment.fileName == "0-Screenshot.png")
        let file = directory.appending(path: item.id).appending(path: attachment.fileName)
        #expect(try Data(contentsOf: file) == Data("png".utf8))
        #expect(item.createdAt == now)
    }
}

func firstValue<Value: Sendable>(_ stream: AsyncThrowingStream<Value, any Error>) async throws -> Value? {
    for try await value in stream { return value }
    return nil
}
