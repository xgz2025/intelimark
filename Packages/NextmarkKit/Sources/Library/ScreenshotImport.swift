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
import GRDB
import Model
import UniformTypeIdentifiers

/// A screenshot read from Photos, ready to become an item.
public struct ImportedScreenshot: Sendable, Equatable {
    /// `PHAsset.localIdentifier`, kept so it can be deleted from Photos later.
    public var assetID: String
    public var data: Data
    /// A uniform type identifier, e.g. `public.png`.
    public var contentType: String
    public var takenAt: Date

    public init(assetID: String, data: Data, contentType: String, takenAt: Date) {
        self.assetID = assetID
        self.data = data
        self.contentType = contentType
        self.takenAt = takenAt
    }
}

/// Screenshot Rescue (PRD C9, Docs/architecture.md §3.2): screenshots go straight into
/// the library, without an envelope, and are queued for enrichment like any capture.
/// Importing the same asset twice does nothing.
public struct ScreenshotImporter: Sendable {
    public let database: LibraryDatabase
    public let itemsDirectory: URL
    public let device: String

    public init(database: LibraryDatabase, itemsDirectory: URL, device: String) {
        self.database = database
        self.itemsDirectory = itemsDirectory
        self.device = device
    }

    /// Imports the screenshots that aren't in the library yet; returns the new item IDs.
    /// Screenshots taken since `recentSince` land in the Inbox like new saves; older
    /// ones go straight to the library, so a big rescue doesn't bury the Inbox.
    @discardableResult
    public func importScreenshots(_ screenshots: [ImportedScreenshot], recentSince: Date, now: Date = Date()) async throws -> [String] {
        let known = try await importedAssetIDs()
        var items: [(ItemRecord, AttachmentRecord)] = []
        for screenshot in screenshots where !known.contains(screenshot.assetID) {
            let id = ULID(date: screenshot.takenAt)
            let fileExtension = UTType(screenshot.contentType)?.preferredFilenameExtension ?? "png"
            let file = PayloadFile(
                fileName: "0-Screenshot.\(fileExtension)", contentType: screenshot.contentType,
                byteSize: Int64(screenshot.data.count)
            )
            let directory = itemsDirectory.appending(path: id.rawValue, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.data.write(to: directory.appending(path: file.fileName), options: .atomic)

            let envelope = CaptureEnvelope(
                id: id, capturedAt: screenshot.takenAt, device: device, surface: .screenshotImport,
                sourceApp: "com.apple.mobileslideshow", payloadFiles: [file]
            )
            var item = ItemRecord(envelope: envelope, now: now)
            item.status = screenshot.takenAt >= recentSince ? .inbox : .active
            item.sourceAssetID = screenshot.assetID
            let attachment = AttachmentRecord(
                itemID: item.id, index: 0, role: .original, fileName: file.fileName,
                contentType: file.contentType, byteSize: file.byteSize, syncPolicy: .ifEnabled
            )
            items.append((item, attachment))
        }
        let toInsert = items
        return try await database.writer.write { db in
            var inserted: [String] = []
            for (item, attachment) in toInsert {
                // Imported meanwhile (e.g. two passes overlapping): keep the first.
                guard try ItemRecord.filter(Column("sourceAssetID") == item.sourceAssetID).isEmpty(db) else { continue }
                try item.insert(db)
                try attachment.insert(db)
                var job = JobRecord(itemID: item.id, stage: .extract, notBefore: now)
                try job.insert(db)
                inserted.append(item.id)
            }
            return inserted
        }
    }

    /// Photos assets already in the library (still in Photos or not).
    public func importedAssetIDs() async throws -> Set<String> {
        try await database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT sourceAssetID FROM item WHERE sourceAssetID IS NOT NULL"))
        }
    }
}

extension ItemRepository {
    /// Everything Screenshot Rescue brought in, newest first (trashed ones left out).
    public func screenshots() -> AsyncThrowingStream<[ItemRecord], any Error> {
        database.observe { db in
            try ItemRecord
                .filter(Column("surface") == CaptureSurface.screenshotImport.rawValue)
                .filter(Column("status") != ItemStatus.trashed.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Photos assets of imported screenshots that are still in Photos; all of them when `itemIDs` is nil.
    public func assetIDsInPhotos(forItems itemIDs: [String]? = nil) async throws -> [String] {
        try await database.writer.read { db in
            var request = ItemRecord.filter(Column("sourceAssetID") != nil)
            if let itemIDs { request = request.filter(itemIDs.contains(Column("id"))) }
            return try request.fetchAll(db).compactMap(\.sourceAssetID)
        }
    }

    /// The assets are gone from Photos; the items stay.
    public func forgetAssets(_ assetIDs: [String]) async throws {
        try await database.writer.write { db in
            for assetID in assetIDs {
                try db.execute(sql: "UPDATE item SET sourceAssetID = NULL WHERE sourceAssetID = ?", arguments: [assetID])
            }
        }
    }

    /// Stores the preview the Extract stage drew.
    public func saveThumbnail(forItem itemID: String, fileName: String, byteSize: Int64?) async throws {
        try await database.writer.write { db in
            guard try ItemRecord.exists(db, key: itemID) else { return }
            try AttachmentRecord.thumbnail(itemID: itemID, fileName: fileName, byteSize: byteSize).upsert(db)
        }
    }
}
