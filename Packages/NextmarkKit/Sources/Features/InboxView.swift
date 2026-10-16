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

struct InboxView: View {
    let services: LibraryServices
    @State private var items: [ItemRecord] = []
    @State private var errorMessage: String?

    private var captures: CaptureStatus { CaptureStatus.shared }

    var body: some View {
        ItemSelectionList(items: items, services: services, date: \.createdAt) {
            if captures.stuckCount > 0 {
                Section {
                    Label(
                        "^[\(captures.stuckCount) save](inflect: true) couldn't be added to your library yet.",
                        systemImage: "exclamationmark.triangle"
                    )
                    if let reason = captures.reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Try Again") {
                        let refresh = services.refresh
                        Task { await refresh() }
                    }
                } footer: {
                    Text("They're kept safe until they can be added. Freeing up storage on this device usually helps.")
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if items.isEmpty, captures.stuckCount == 0, errorMessage == nil {
                ContentUnavailableView("Nothing Saved Yet", systemImage: "tray", description: Text(Self.emptyHint))
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddMenu(services: services)
            }
        }
        .task {
            do {
                for try await snapshot in services.items.inboxItems() {
                    items = snapshot
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    static var emptyHint: LocalizedStringKey {
        #if os(macOS)
        "Click + to add a note, link, photo or file. In other apps, click Share and choose Laterwise, or use Quick Capture from the menu bar."
        #else
        "Tap + to add a note, link, photo or file. In other apps, tap Share and choose Laterwise."
        #endif
    }
}

/// Items finished with: out of the Inbox, still in their groups and in Search.
struct DoneView: View {
    let services: LibraryServices
    @State private var items: [ItemRecord] = []

    var body: some View {
        ItemSelectionList(items: items, services: services, date: \.updatedAt) {
            EmptyView()
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing Done Yet", systemImage: "checkmark.circle",
                    description: Text("Items you mark as done leave the Inbox and wait here. They stay in their groups and in Search.")
                )
            }
        }
        .navigationTitle("Done")
        .task {
            for await snapshot in services.items.doneItems().ignoringErrors() {
                items = snapshot
            }
        }
    }
}

/// Items by day. Click or tap one to open it; swipe to finish or trash it; or
/// choose Select to act on several at once (on the Mac, ⌘- and ⇧-click, ⌘A and Delete).
struct ItemSelectionList<Header: View>: View {
    let items: [ItemRecord]
    let services: LibraryServices
    let date: (ItemRecord) -> Date
    @ViewBuilder let header: () -> Header
    @State private var selection = Set<String>()
    @State private var isSelecting = false
    @State private var showsAddToGroup = false

    /// Done items are brought back; everything else is finished.
    private var showsDoneItems: Bool {
        !items.isEmpty && items.allSatisfy { $0.status == .done }
    }

    var body: some View {
        Group {
            if isSelecting {
                List(selection: $selection) {
                    header()
                    rows(selectable: true)
                }
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #else
                .onDeleteCommand { apply(.trashed) }
                #endif
            } else {
                List {
                    header()
                    rows(selectable: false)
                }
            }
        }
        .toolbar { toolbar }
        .onChange(of: items.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if ids.isEmpty { isSelecting = false }
        }
        .sheet(isPresented: $showsAddToGroup) {
            AddToGroupSheet(itemIDs: Array(selection), services: services)
        }
    }

    @ViewBuilder
    private func rows(selectable: Bool) -> some View {
        ForEach(DaySection.sections(of: items, date: date)) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    if selectable {
                        ItemRow(item: item).id(item.rowVersion).tag(item.id)
                    } else {
                        ItemLinkRow(item: item, services: services)
                            .swipeActions(edge: .leading) {
                                if item.status == .done {
                                    Button("Not Done", systemImage: "arrow.uturn.backward") {
                                        changeStatus(.active, of: [item], using: services.items)
                                    }
                                    .tint(.blue)
                                } else {
                                    Button("Done", systemImage: "checkmark") {
                                        changeStatus(.done, of: [item], using: services.items)
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Trash", systemImage: "trash", role: .destructive) {
                                    changeStatus(.trashed, of: [item], using: services.items)
                                }
                            }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { endSelecting() }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .primaryAction) {
                let allSelected = selection.count == items.count
                Button(allSelected ? LocalizedStringKey("Deselect All") : "Select All") {
                    selection = allSelected ? [] : Set(items.map(\.id))
                }
            }
            ToolbarItemGroup(placement: Self.bulkPlacement) {
                if showsDoneItems {
                    Button { apply(.active) } label: {
                        Label("Mark as Not Done", systemImage: "arrow.uturn.backward")
                    }
                    .help(Text("Move the selected items back to the Inbox"))
                    .disabled(selection.isEmpty)
                } else {
                    Button { apply(.done) } label: {
                        Label("Mark as Done", systemImage: "checkmark.circle")
                    }
                    .help(Text("Mark the selected items as done: they leave the Inbox and wait in Done"))
                    .disabled(selection.isEmpty)
                }
                Button { showsAddToGroup = true } label: {
                    Label("Add to Group…", systemImage: "square.stack")
                }
                .help(Text("Add the selected items to a group"))
                .disabled(selection.isEmpty)
                #if os(iOS)
                Spacer()
                #endif
                Button(role: .destructive) { apply(.trashed) } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .help(Text("Move the selected items to the Trash"))
                .disabled(selection.isEmpty)
            }
        } else if !items.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button("Select") { isSelecting = true }
                    .help(Text("Choose several items to mark them done, add them to a group or move them to the Trash"))
            }
        }
    }

    private static var bulkPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .primaryAction
        #endif
    }

    private func apply(_ status: ItemStatus) {
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        changeStatus(status, of: chosen, using: services.items)
        endSelecting()
    }

    private func endSelecting() {
        selection = []
        isSelecting = false
    }
}

/// Items by when they were saved: Today, Yesterday, This Week, Earlier.
struct DaySection<Element: Identifiable>: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let items: [Element]

    static func sections(
        of items: [Element], date: (Element) -> Date, now: Date = Date(), calendar: Calendar = .current
    ) -> [DaySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        var buckets: [[Element]] = [[], [], [], []]
        for item in items {
            let day = date(item)
            let index = day >= today ? 0 : day >= yesterday ? 1 : day >= weekAgo ? 2 : 3
            buckets[index].append(item)
        }
        let titles: [LocalizedStringKey] = ["Today", "Yesterday", "This Week", "Earlier"]
        return buckets.indices
            .filter { !buckets[$0].isEmpty }
            .map { DaySection(id: $0, title: titles[$0], items: buckets[$0]) }
    }
}
