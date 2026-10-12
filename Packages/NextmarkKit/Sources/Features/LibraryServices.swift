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
import SwiftUI
import Library
import Search

/// What the screens need from the library, injected by the app.
public struct LibraryServices: Sendable {
    public let items: ItemRepository
    public let groups: GroupRepository
    public let actions: ActionRepository
    public let search: HybridSearch
    /// Runs ingestion and enrichment now, e.g. after asking for a Brief to be rewritten.
    public let refresh: @Sendable () async -> Void
    /// Fetches from and sends to iCloud now.
    public let syncNow: @Sendable () async -> Void
    /// Where each item's files live (`<itemsDirectory>/<itemID>/…`).
    public let itemsDirectory: URL?

    public init(
        database: LibraryDatabase,
        search: HybridSearch,
        itemsDirectory: URL? = nil,
        refresh: @escaping @Sendable () async -> Void,
        syncNow: @escaping @Sendable () async -> Void = {}
    ) {
        self.itemsDirectory = itemsDirectory
        items = ItemRepository(database: database)
        groups = GroupRepository(database: database)
        actions = ActionRepository(database: database)
        self.search = search
        self.refresh = refresh
        self.syncNow = syncNow
    }
}

extension ItemRecord {
    /// The preview of an image or PDF item, drawn by the Extract stage.
    func thumbnailURL(in itemsDirectory: URL?) -> URL? {
        guard let itemsDirectory, [.image, .pdf].contains(kind) else { return nil }
        return itemsDirectory.appending(path: id).appending(path: "thumbnail.jpg")
    }
}

extension EnvironmentValues {
    /// Lets rows find item previews without passing services down.
    @Entry var itemsDirectory: URL? = nil
}

/// Navigates to an item's screen.
struct ItemLink: Hashable {
    let id: String
}
