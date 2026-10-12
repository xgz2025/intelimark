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
import Library

/// A screenshot in the user's photo library.
public struct ScreenshotRef: Sendable, Hashable {
    public var id: String
    public var takenAt: Date

    public init(id: String, takenAt: Date) {
        self.id = id
        self.takenAt = takenAt
    }
}

public enum PhotosAccess: Sendable, Equatable {
    case notDetermined
    /// Full or limited: Nextmark sees what the user chose to share.
    case granted
    case denied
}

/// Where screenshots come from: Photos in the app, a fake in tests.
public protocol ScreenshotSource: Sendable {
    func access() -> PhotosAccess
    func requestAccess() async -> PhotosAccess
    /// Newest first.
    func screenshots() async -> [ScreenshotRef]
    func load(_ screenshot: ScreenshotRef) async -> ImportedScreenshot?
    /// Asks the user (the system shows its own confirmation), then deletes.
    func delete(_ ids: [String]) async throws
}

public struct RescueProgress: Sendable, Equatable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// Screenshot Rescue (PRD C9): brings the screenshots in Photos into the library,
/// newest first and in batches, so the first ones are sorted while the rest load.
/// Afterwards it offers to delete them from Photos; they stay in Nextmark.
public actor ScreenshotRescue {
    public static let batchSize = 50
    /// Screenshots newer than this land in the Inbox; older ones go straight to the library.
    public static let recentInterval: TimeInterval = 7 * 86_400

    private let source: any ScreenshotSource
    private let importer: ScreenshotImporter
    private let repository: ItemRepository

    public init(source: any ScreenshotSource, importer: ScreenshotImporter) {
        self.source = source
        self.importer = importer
        repository = ItemRepository(database: importer.database)
    }

    public nonisolated func access() -> PhotosAccess {
        source.access()
    }

    public func requestAccess() async -> PhotosAccess {
        await source.requestAccess()
    }

    /// Screenshots in Photos that aren't in the library yet.
    public func pending() async -> [ScreenshotRef] {
        guard source.access() == .granted else { return [] }
        let known = (try? await importer.importedAssetIDs()) ?? []
        return await source.screenshots().filter { !known.contains($0.id) }
    }

    /// How many screenshots Photos has (the onboarding's "You have 2,341 screenshots").
    public func screenshotCount() async -> Int {
        guard source.access() == .granted else { return 0 }
        return await source.screenshots().count
    }

    /// Imports every pending screenshot. Reports progress after each batch and
    /// stops between batches when the task is cancelled. Returns how many were imported.
    @discardableResult
    public func run(
        now: Date = Date(),
        onBatch: @escaping @Sendable (RescueProgress) async -> Void = { _ in }
    ) async throws -> Int {
        let pending = await pending()
        var progress = RescueProgress(done: 0, total: pending.count)
        await onBatch(progress)
        var imported = 0
        var start = pending.startIndex
        while start < pending.endIndex {
            try Task.checkCancellation()
            let batch = pending[start..<min(start + Self.batchSize, pending.endIndex)]
            // One at a time: a batch of full-size iPad screenshots held in memory together
            // could get the background task stopped.
            for ref in batch {
                guard let screenshot = await source.load(ref) else { continue }
                imported += try await importer.importScreenshots(
                    [screenshot], recentSince: now.addingTimeInterval(-Self.recentInterval), now: now
                ).count
            }
            start = batch.endIndex
            progress.done = start - pending.startIndex
            await onBatch(progress)
        }
        return imported
    }

    /// How many imported screenshots are still in Photos.
    public func inPhotosCount() async -> Int {
        (try? await repository.assetIDsInPhotos().count) ?? 0
    }

    /// Deletes imported screenshots from Photos (all of them when `itemIDs` is nil).
    /// The system asks the user to confirm. Returns how many were deleted.
    @discardableResult
    public func cleanUpPhotos(itemIDs: [String]? = nil) async throws -> Int {
        let assetIDs = try await repository.assetIDsInPhotos(forItems: itemIDs)
        guard !assetIDs.isEmpty else { return 0 }
        try await source.delete(assetIDs)
        try await repository.forgetAssets(assetIDs)
        return assetIDs.count
    }
}
