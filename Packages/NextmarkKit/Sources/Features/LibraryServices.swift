import Foundation
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

    public init(
        database: LibraryDatabase,
        search: HybridSearch,
        refresh: @escaping @Sendable () async -> Void,
        syncNow: @escaping @Sendable () async -> Void = {}
    ) {
        items = ItemRepository(database: database)
        groups = GroupRepository(database: database)
        actions = ActionRepository(database: database)
        self.search = search
        self.refresh = refresh
        self.syncNow = syncNow
    }
}

/// Navigates to an item's screen.
struct ItemLink: Hashable {
    let id: String
}
