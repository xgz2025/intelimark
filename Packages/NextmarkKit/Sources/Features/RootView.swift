import SwiftUI
import Library
import Moments

enum SidebarSelection: Hashable {
    case inbox, nextActions, review, search, suggestions, settings
    case group(String)
}

/// Top-level navigation: a sidebar on iPad and Mac that collapses to a stack on
/// iPhone. Groups are listed in the sidebar and accept items dragged onto them (PRD G1).
public struct RootView: View {
    private let services: LibraryServices
    private let navigator: AppNavigator
    @State private var selection: SidebarSelection? = .inbox
    @State private var path = NavigationPath()
    @State private var groups: [GroupSummary] = []
    @State private var suggestionCount = 0
    @State private var openActionCount = 0
    @State private var showsNewGroup = false

    public init(services: LibraryServices, navigator: AppNavigator = AppNavigator()) {
        self.services = services
        self.navigator = navigator
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                detail(for: selection ?? .inbox)
                    .navigationDestination(for: ItemLink.self) { link in
                        ItemDetailView(itemID: link.id, services: services)
                    }
                    .navigationDestination(for: GroupLink.self) { link in
                        GroupDetailView(groupID: link.id, services: services)
                    }
            }
        }
        .onChange(of: selection) {
            path = NavigationPath()
        }
        .onChange(of: navigator.destination) {
            guard let destination = navigator.destination else { return }
            navigator.destination = nil
            open(destination)
        }
        .task {
            for await summaries in services.groups.summaries(states: [.accepted, .suggested]).ignoringErrors() {
                groups = summaries.filter { $0.group.state == .accepted }
                suggestionCount = summaries.count - groups.count
            }
        }
        .task {
            for await actions in services.actions.nextActions().ignoringErrors() {
                openActionCount = actions.count
            }
        }
        .sheet(isPresented: $showsNewGroup) {
            NewGroupSheet(services: services) { id in
                selection = .group(id)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Inbox", systemImage: "tray")
                    .tag(SidebarSelection.inbox)
                Label("Next Actions", systemImage: "checklist")
                    .badge(openActionCount)
                    .tag(SidebarSelection.nextActions)
                Label("Weekly Review", systemImage: "rectangle.stack")
                    .tag(SidebarSelection.review)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarSelection.search)
            }
            Section("Groups") {
                if suggestionCount > 0 {
                    Label("Suggestions", systemImage: "sparkles")
                        .badge(suggestionCount)
                        .tag(SidebarSelection.suggestions)
                }
                ForEach(groups) { summary in
                    GroupSidebarRow(summary: summary)
                        .tag(SidebarSelection.group(summary.id))
                        .dropDestination(for: String.self) { ids, _ in
                            let (repository, groupID) = (services.groups, summary.id)
                            Task { _ = try? await repository.addItems(ids, to: groupID) }
                            return true
                        }
                }
                Button {
                    showsNewGroup = true
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            #if os(iOS)
            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
            #endif
        }
        .navigationTitle("Nextmark")
    }

    @ViewBuilder
    private func detail(for selection: SidebarSelection) -> some View {
        switch selection {
        case .inbox:
            InboxView(services: services)
        case .nextActions:
            NextActionsView(services: services)
        case .review:
            WeeklyReviewView(services: services)
        case .search:
            SearchView(services: services)
        case .suggestions:
            SuggestionsView(services: services)
        case .settings:
            SettingsView(onChange: services.refresh)
        case .group(let id):
            GroupDetailView(groupID: id, services: services)
                .id(id)
        }
    }
}

extension RootView {
    /// Follows a notification tap (PRD M1, M2).
    private func open(_ destination: MomentDestination) {
        switch destination {
        case .item(let id):
            path.append(ItemLink(id: id))
        case .group(let id):
            selection = .group(id)
        case .nextActions:
            selection = .nextActions
        case .weeklyReview:
            selection = .review
        }
    }
}

private struct GroupSidebarRow: View {
    let summary: GroupSummary

    var body: some View {
        HStack {
            Text(summary.group.emoji ?? "📁")
                .accessibilityHidden(true)
            Text(summary.group.displayTitle)
                .lineLimit(1)
                .foregroundStyle(summary.group.status == .done ? .secondary : .primary)
        }
        .badge(summary.suggestedCount > 0 ? Text("\(summary.suggestedCount) new") : nil)
    }
}
