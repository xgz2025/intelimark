import SwiftUI
import Library
import Search

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case inbox, nextActions, groups, search, settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .inbox: "Inbox"
        case .nextActions: "Next Actions"
        case .groups: "Groups"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .nextActions: "checklist"
        case .groups: "square.stack"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

/// Top-level navigation: a sidebar on iPad and Mac that collapses to a stack on iPhone.
public struct RootView: View {
    private let repository: ItemRepository
    private let search: HybridSearch
    @State private var selection: SidebarItem? = .inbox

    public init(repository: ItemRepository, search: HybridSearch) {
        self.repository = repository
        self.search = search
    }

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbolName)
            }
            .navigationTitle("Nextmark")
        } detail: {
            NavigationStack {
                detail(for: selection ?? .inbox)
            }
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .inbox:
            InboxView(repository: repository)
        case .search:
            SearchView(search: search)
        case .settings:
            SettingsView()
        case .nextActions:
            ContentUnavailableView(
                "Next Actions", systemImage: "checklist",
                description: Text("Actions from your saves and groups will appear here.")
            )
        case .groups:
            ContentUnavailableView(
                "Groups", systemImage: "square.stack",
                description: Text("Suggested groups and plans will appear here.")
            )
        }
    }
}
