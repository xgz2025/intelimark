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

/// The Trash: items moved there stay restorable until it's emptied, by the user or
/// after `retention`. Deleting removes the row (with its attachments, memberships,
/// actions and vector, by cascade), its files, and, through sync, its copies on
/// the user's other devices.
extension ItemRepository {
    /// Trashed items are deleted for good after this long in the Trash.
    public static let trashRetention: TimeInterval = 30 * 86_400

    /// Live list of the Trash, most recently trashed first.
    public func trashedItems() -> AsyncThrowingStream<[ItemRecord], any Error> {
        database.observe { db in
            try ItemRecord
                .filter(Column("status") == ItemStatus.trashed.rawValue)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func trashCount() -> AsyncThrowingStream<Int, any Error> {
        database.observe { db in
            try ItemRecord.filter(Column("status") == ItemStatus.trashed.rawValue).fetchCount(db)
        }
    }

    /// Takes items out of the Trash, back into the library.
    public func restore(_ ids: [String], now: Date = Date()) async throws {
        try await database.writer.write { db in
            for id in ids {
                guard var item = try ItemRecord.fetchOne(db, key: id), item.status == .trashed else { continue }
                item.status = .active
                item.updatedAt = now
                try item.update(db)
            }
        }
    }

    /// Deletes items for good. Their files go from `itemsDirectory`; screenshots still in
    /// Photos are remembered, so Screenshot Rescue doesn't import them again.
    public func deletePermanently(_ ids: [String], itemsDirectory: URL?) async throws {
        guard !ids.isEmpty else { return }
        try await database.writer.write { db in
            for id in ids {
                guard let item = try ItemRecord.fetchOne(db, key: id) else { continue }
                if let assetID = item.sourceAssetID {
                    try db.execute(sql: "INSERT OR IGNORE INTO ignoredAsset (assetID) VALUES (?)", arguments: [assetID])
                }
                try db.execute(sql: "DELETE FROM job WHERE itemID = ?", arguments: [id])
                _ = try item.delete(db)
            }
        }
        guard let itemsDirectory else { return }
        for id in ids {
            Self.removeFiles(ofItem: id, in: itemsDirectory)
        }
    }

    /// Empties the Trash. Returns how many items were deleted.
    @discardableResult
    public func emptyTrash(itemsDirectory: URL?) async throws -> Int {
        let ids = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM item WHERE status = ?", arguments: [ItemStatus.trashed.rawValue])
        }
        try await deletePermanently(ids, itemsDirectory: itemsDirectory)
        return ids.count
    }

    /// Deletes items that have been in the Trash longer than `trashRetention`.
    @discardableResult
    public func purgeTrash(itemsDirectory: URL?, now: Date = Date()) async throws -> Int {
        let cutoff = now.addingTimeInterval(-Self.trashRetention)
        let ids = try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT id FROM item WHERE status = ? AND updatedAt < ?",
                arguments: [ItemStatus.trashed.rawValue, cutoff]
            )
        }
        try await deletePermanently(ids, itemsDirectory: itemsDirectory)
        return ids.count
    }

    /// An item's folder of files (`<itemsDirectory>/<itemID>`). IDs never contain "/".
    public static func removeFiles(ofItem id: String, in itemsDirectory: URL) {
        guard !id.isEmpty, !id.contains("/"), !id.hasPrefix(".") else { return }
        try? FileManager.default.removeItem(at: itemsDirectory.appending(path: id, directoryHint: .isDirectory))
    }
}
