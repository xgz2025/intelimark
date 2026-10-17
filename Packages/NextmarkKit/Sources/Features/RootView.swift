//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import SwiftUI
import Model
import Library
import Moments
import Integrations

enum SidebarSelection: Hashable {
    case inbox, upcoming, nextActions, review, search, suggestions, screenshots, done, trash, settings
    case group(String)
}

/// Top-level navigation: a sidebar on iPad and Mac that collapses to a stack on
/// iPhone. Groups are listed in the sidebar and accept items dragged onto them (PRD G1).
public struct RootView: View {
    private let services: LibraryServices
    private let navigator: AppNavigator
    private let rescue: RescueController?
    @AppStorage(OnboardingView.completedKey) private var onboarded = false
    @State private var selection: SidebarSelection? = .inbox
    @State private var path = NavigationPath()
    @State private var groups: [GroupSummary] = []
    @State private var suggestionCount = 0
    @State private var openActionCount = 0
    @State private var trashCount = 0
    @State private var showsNewGroup = false
    @State private var showsNewNote = false
    @State private var renamingGroup: GroupRecord?
    @State private var deletingGroup: GroupRecord?

    /// - Parameter rescue: Screenshot Rescue, where the device has a photo library to rescue from.
    public init(services: LibraryServices, navigator: AppNavigator = AppNavigator(), rescue: RescueController? = nil) {
        self.services = services
        self.navigator = navigator
        self.rescue = rescue
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
        .environment(\.itemsDirectory, services.itemsDirectory)
        .onChange(of: selection) {
            path = NavigationPath()
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView(rescue: rescue) { startedRescue in
                onboarded = true
                if startedRescue { selection = .screenshots }
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: navigator.command, initial: true) {
            guard let command = navigator.command else { return }
            navigator.command = nil
            switch command {
            case .newNote: showsNewNote = true
            case .newGroup: showsNewGroup = true
            case .search: selection = .search
            }
        }
        .sheet(isPresented: $showsNewNote) {
            NewNoteSheet(services: services)
        }
        .sheet(item: $renamingGroup) { group in
            RenameGroupSheet(group: group, services: services)
        }
        .confirmationDialog(
            "Delete “\(deletingGroup?.displayTitle ?? "")”?",
            isPresented: Binding(get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }),
            titleVisibility: .visible,
            presenting: deletingGroup
        ) { group in
            Button("Delete Group", role: .destructive) {
                let (groups, id) = (services.groups, group.id)
                performEdit { try await groups.delete(id) }
            }
        } message: { _ in
            Text("Its items stay in your library. The group's own actions are deleted with it.")
        }
        .onChange(of: navigator.destination, initial: true) {
            // `initial`: a notification tap that launched the app arrives before this view.
            guard let destination = navigator.destination else { return }
            navigator.destination = nil
            open(destination)
        }
        .task {
            for await summaries in services.groups.summaries(states: [.accepted, .suggested]).ignoringErrors() {
                groups = summaries.filter { $0.group.state == .accepted }
                suggestionCount = summaries.count - groups.count
                // A deleted or merged group leaves the sidebar; don't stay on its empty screen.
                if case .group(let id) = selection, !groups.contains(where: { $0.id == id }) {
                    selection = .inbox
                }
            }
        }
        .task {
            for await actions in services.actions.nextActions().ignoringErrors() {
                openActionCount = actions.count
            }
        }
        .task {
            for await count in services.items.trashCount().ignoringErrors() {
                trashCount = count
            }
        }
        .recentChangeBanner(items: services.items)
        .editFailureAlert()
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
                Label("Upcoming", systemImage: "calendar")
                    .tag(SidebarSelection.upcoming)
                Label("Next Actions", systemImage: "checklist")
                    .badge(openActionCount)
                    .tag(SidebarSelection.nextActions)
                Label("Weekly Review", systemImage: "rectangle.stack")
                    .tag(SidebarSelection.review)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarSelection.search)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
                if rescue != nil {
                    Label("Screenshots", systemImage: "camera.viewfinder")
                        .tag(SidebarSelection.screenshots)
                }
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
                        .dropDestination(for: String.self) { dropped, _ in
                            // Items drag as their IDs; other text dropped here isn't an item.
                            let ids = dropped.filter { ULID($0) != nil }
                            guard !ids.isEmpty else { return false }
                            let (repository, groupID) = (services.groups, summary.id)
                            Task { @MainActor in
                                do {
                                    _ = try await repository.addItems(ids, to: groupID)
                                } catch {
                                    EditFailure.shared.report(error)
                                }
                            }
                            return true
                        }
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") { renamingGroup = summary.group }
                            Divider()
                            Button("Delete Group…", systemImage: "trash", role: .destructive) { deletingGroup = summary.group }
                        }
                }
                Button {
                    showsNewGroup = true
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            Section {
                Label("Done", systemImage: "checkmark.circle")
                    .tag(SidebarSelection.done)
                Label("Trash", systemImage: "trash")
                    .badge(trashCount)
                    .tag(SidebarSelection.trash)
            }
        }
        .navigationTitle("Laterwise")
    }

    @ViewBuilder
    private func detail(for selection: SidebarSelection) -> some View {
        switch selection {
        case .inbox:
            InboxView(services: services)
        case .upcoming:
            UpcomingView(services: services)
        case .nextActions:
            NextActionsView(services: services)
        case .review:
            WeeklyReviewView(services: services)
        case .search:
            SearchView(services: services)
        case .suggestions:
            SuggestionsView(services: services)
        case .screenshots:
            if let rescue {
                ScreenshotRescueView(services: services, controller: rescue)
            }
        case .done:
            DoneView(services: services)
        case .trash:
            TrashView(services: services)
        case .settings:
            SettingsView(onChange: services.refresh, onSyncNow: services.syncNow)
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
            if selection == nil {
                // On iPhone the detail column isn't showing while the sidebar is. Choosing
                // the Inbox resets the path, so the item goes on after that has happened.
                selection = .inbox
                Task { @MainActor in path.append(ItemLink(id: id)) }
            } else {
                path.append(ItemLink(id: id))
            }
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
