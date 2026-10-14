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
import DesignSystem

/// An item in a list: opens the item, drags onto a group (PRD G1), and offers
/// Add to Group, Add Action and Done from its context menu.
struct ItemLinkRow: View {
    let item: ItemRecord
    let services: LibraryServices
    @State private var showsAddToGroup = false
    @State private var showsAddAction = false

    var body: some View {
        NavigationLink(value: ItemLink(id: item.id)) {
            ItemRow(item: item)
        }
        .draggable(item.id)
        .contextMenu {
            if let link = item.anchorURL ?? item.canonicalURL.flatMap({ URL(string: $0) }) {
                Link(destination: link) {
                    Label("Open", systemImage: "safari")
                }
                ShareLink(item: link)
                Divider()
            }
            Button("Add to Group…", systemImage: "square.stack") { showsAddToGroup = true }
            Button("Add Action…", systemImage: "checklist") { showsAddAction = true }
            Divider()
            if item.status == .done {
                Button("Mark as Not Done", systemImage: "arrow.uturn.backward") { setStatus(.active) }
            } else {
                Button("Mark as Done", systemImage: "checkmark.circle") { setStatus(.done) }
            }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) { setStatus(.trashed) }
        }
        .sheet(isPresented: $showsAddToGroup) {
            AddToGroupSheet(itemIDs: [item.id], services: services)
        }
        .sheet(isPresented: $showsAddAction) {
            NewActionSheet(itemID: item.id, groupID: nil, services: services)
        }
    }

    private func setStatus(_ status: ItemStatus) {
        let (items, id) = (services.items, item.id)
        performEdit { try await items.setStatus(status, forItem: id) }
    }
}

/// A checkable action (PRD A1).
struct ActionRow: View {
    let action: ActionRecord
    var context: String?
    let onToggle: () -> Void

    private var isDone: Bool { action.status == .done }

    private var isOverdue: Bool {
        guard let due = action.dueAt, !isDone else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? Text("Mark as not done") : Text("Mark as done"))

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                if action.dueAt != nil || context != nil {
                    HStack(spacing: 8) {
                        if let due = action.dueAt {
                            Label(due.formatted(.relative(presentation: .named)), systemImage: "calendar")
                                .foregroundStyle(isOverdue ? .red : .secondary)
                        }
                        if let context {
                            Text(context).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A suggested action with one-tap Add and Dismiss (PRD A2).
struct SuggestedActionRow: View {
    let suggestion: SuggestedAction
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                if let due = suggestion.dueAt {
                    Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Add", systemImage: "plus.circle.fill", action: onAdd)
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }
}

/// A new action with an optional due date.
struct NewActionSheet: View {
    let itemID: String?
    let groupID: String?
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Action", text: $title, prompt: Text("What's the next step?"))
                Toggle("Due Date", isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: [.date])
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Action")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }

    private func add() {
        let due: Date? = hasDueDate ? dueDate : nil
        let (actions, title, itemID, groupID) = (services.actions, title, itemID, groupID)
        performEdit { _ = try await actions.add(title: title, dueAt: due, itemID: itemID, groupID: groupID) }
        dismiss()
    }
}

/// Emoji offered for new groups; any emoji can be typed instead.
let groupEmoji = ["🧳", "🍜", "🛒", "🏠", "🎁", "📚", "💼", "🎟️", "🍳", "💡", "🎯", "🌿"]

/// A new manual group, optionally with items in it (PRD G1).
struct NewGroupSheet: View {
    var itemIDs: [String] = []
    let services: LibraryServices
    var onCreate: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var emoji = groupEmoji[0]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $title, prompt: Text("Kyoto trip, New desk…"))
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(groupEmoji, id: \.self) { candidate in
                            Button {
                                emoji = candidate
                            } label: {
                                Text(candidate)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(candidate == emoji ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(candidate == emoji ? .isSelected : [])
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    private func create() {
        let (groups, title, emoji, itemIDs) = (services.groups, title, emoji, itemIDs)
        let onCreate = onCreate
        performEdit {
            let id = try await groups.createGroup(title: title, emoji: emoji, itemIDs: itemIDs)
            onCreate(id)
        }
        dismiss()
    }
}

/// Picks a group for some items, or makes a new one.
struct AddToGroupSheet: View {
    let itemIDs: [String]
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [GroupSummary] = []
    @State private var showsNewGroup = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showsNewGroup = true
                } label: {
                    Label("New Group…", systemImage: "plus")
                }
                ForEach(groups) { summary in
                    Button {
                        add(to: summary.id)
                    } label: {
                        GroupLabel(group: summary.group, count: summary.memberCount)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add to Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                for await summaries in services.groups.summaries().ignoringErrors() {
                    groups = summaries.filter { $0.group.status == .active }
                }
            }
            .sheet(isPresented: $showsNewGroup, onDismiss: { dismiss() }) {
                NewGroupSheet(itemIDs: itemIDs, services: services)
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    private func add(to groupID: String) {
        let (groups, itemIDs) = (services.groups, itemIDs)
        performEdit { _ = try await groups.addItems(itemIDs, to: groupID) }
        dismiss()
    }
}

/// A group's emoji, name and member count.
struct GroupLabel: View {
    let group: GroupRecord
    var count: Int?

    var body: some View {
        HStack {
            Text(group.emoji ?? "📁")
                .accessibilityHidden(true)
            Text(group.displayTitle)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
    }
}

extension AsyncThrowingStream where Element: Sendable {
    /// The values until the stream fails; a failed observation just stops updating.
    func ignoringErrors() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await value in self { continuation.yield(value) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
