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
import Testing
import Model
@testable import Library

struct TrashTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    let database: LibraryDatabase
    let repository: ItemRepository
    let itemsDirectory = FileManager.default.temporaryDirectory.appending(path: "TrashTests-\(UUID().uuidString)")

    init() throws {
        database = try LibraryDatabase.inMemory()
        repository = ItemRepository(database: database)
    }

    private func screenshot(_ assetID: String, takenAt: Date) -> ImportedScreenshot {
        ImportedScreenshot(assetID: assetID, data: Data("png".utf8), contentType: "public.png", takenAt: takenAt)
    }

    private func importScreenshots(_ assetIDs: [String]) async throws -> [String] {
        let importer = ScreenshotImporter(database: database, itemsDirectory: itemsDirectory, device: "phone")
        return try await importer.importScreenshots(
            assetIDs.map { screenshot($0, takenAt: now) }, recentSince: now, now: now
        )
    }

    @Test func severalItemsChangeAtOnce() async throws {
        let ids = try await importScreenshots(["a", "b", "c"])
        try await repository.setStatus(.done, forItems: [ids[0], ids[1]], now: now)
        #expect(try await repository.item(id: ids[0])?.status == .done)
        #expect(try await repository.item(id: ids[1])?.status == .done)
        #expect(try await repository.item(id: ids[2])?.status != .done)
    }

    @Test func restoreBringsAnItemBack() async throws {
        let ids = try await importScreenshots(["a"])
        try await repository.setStatus(.trashed, forItem: ids[0], now: now)
        try await repository.restore(ids, now: now)
        #expect(try await repository.item(id: ids[0])?.status == .active)
    }

    @Test func deletingForGoodRemovesTheRowAndItsFiles() async throws {
        let ids = try await importScreenshots(["a", "b"])
        let folder = itemsDirectory.appending(path: ids[0], directoryHint: .isDirectory)
        #expect(FileManager.default.fileExists(atPath: folder.path()))

        try await repository.setStatus(.trashed, forItem: ids[0], now: now)
        let deleted = try await repository.emptyTrash(itemsDirectory: itemsDirectory)

        #expect(deleted == 1)
        #expect(try await repository.item(id: ids[0]) == nil)
        #expect(try await repository.item(id: ids[1]) != nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path()))
    }

    @Test func aDeletedScreenshotIsNotImportedAgain() async throws {
        let ids = try await importScreenshots(["a"])
        try await repository.deletePermanently(ids, itemsDirectory: itemsDirectory)

        let importer = ScreenshotImporter(database: database, itemsDirectory: itemsDirectory, device: "phone")
        #expect(try await importer.importedAssetIDs().contains("a"))
        #expect(try await importScreenshots(["a"]).isEmpty)
    }

    @Test func purgeDeletesOnlyItemsTrashedLongAgo() async throws {
        let ids = try await importScreenshots(["old", "new"])
        try await repository.setStatus(.trashed, forItem: ids[0], now: now.addingTimeInterval(-31 * 86_400))
        try await repository.setStatus(.trashed, forItem: ids[1], now: now.addingTimeInterval(-29 * 86_400))

        let purged = try await repository.purgeTrash(itemsDirectory: itemsDirectory, now: now)

        #expect(purged == 1)
        #expect(try await repository.item(id: ids[0]) == nil)
        #expect(try await repository.item(id: ids[1])?.status == .trashed)
    }
}

struct DatabaseLocationTests {
    @Test func aLegacyLibraryMovesWithItsLog() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DatabaseLocationTests-\(UUID().uuidString)")
        let legacy = root.appending(path: "Group/Database/library.sqlite")
        let current = root.appending(path: "App/Database/library.sqlite")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try LibraryDatabase.onDisk(at: legacy)

        #expect(LibraryDatabase.moveLegacyDatabase(from: legacy, to: current) == current)

        #expect(!FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: current.path(percentEncoded: false)))
        _ = try LibraryDatabase.onDisk(at: current)
        // Nothing to move the second time.
        #expect(LibraryDatabase.moveLegacyDatabase(from: legacy, to: current) == current)
        #expect(FileManager.default.fileExists(atPath: current.path(percentEncoded: false)))
    }

    @Test func aLibraryThatCantMoveStaysWhereItIs() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "DatabaseLocationTests-\(UUID().uuidString)")
        let legacy = root.appending(path: "Group/library.sqlite")
        let current = root.appending(path: "App/library.sqlite")
        try fileManager.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        for path in [legacy.path(percentEncoded: false), legacy.path(percentEncoded: false) + "-wal",
                     legacy.path(percentEncoded: false) + "-shm", current.path(percentEncoded: false) + "-shm"] {
            #expect(fileManager.createFile(atPath: path, contents: Data("x".utf8)))
        }

        // The log moves, the shared memory file can't (one is already there): all goes back.
        #expect(LibraryDatabase.moveLegacyDatabase(from: legacy, to: current) == legacy)
        #expect(fileManager.fileExists(atPath: legacy.path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: legacy.path(percentEncoded: false) + "-wal"))
        #expect(!fileManager.fileExists(atPath: current.path(percentEncoded: false)))
        #expect(!fileManager.fileExists(atPath: current.path(percentEncoded: false) + "-wal"))
    }
}
