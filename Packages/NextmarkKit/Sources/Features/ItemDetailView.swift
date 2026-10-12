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
import Intelligence
import DesignSystem

/// One item: what it is, why it was saved, its groups and its next steps.
struct ItemDetailView: View {
    let itemID: String
    let services: LibraryServices
    @State private var item: ItemRecord?
    @State private var context = ItemContext()
    @State private var newAction = ""
    @State private var showsAddToGroup = false
    @State private var showsDonePrompt = false

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ProgressView()
            }
        }
        .task(id: itemID) {
            // Opening an item keeps it out of the stale pile in the Weekly Review.
            try? await services.items.markOpened(itemID)
            for await value in services.items.observeItem(id: itemID).ignoringErrors() {
                item = value
            }
        }
        .task(id: itemID) {
            for await value in services.groups.context(forItem: itemID).ignoringErrors() {
                context = value
            }
        }
    }

    private func content(_ item: ItemRecord) -> some View {
        let suggestions = ActionSuggester.suggestions(for: item.digest)
            .filter { !context.knownActionTitles.contains($0.title.lowercased()) }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let preview = item.thumbnailURL(in: services.itemsDirectory) {
                        AsyncImage(url: preview) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            EmptyView()
                        }
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                        .id(item.updatedAt)
                    }
                    Text(item.displayTitle)
                        .font(.title2.bold())
                    if let subtitle = item.subtitle, subtitle != item.summary {
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                    }
                    if let link = item.anchorURL ?? item.canonicalURL.flatMap({ URL(string: $0) }) {
                        Link(destination: link) {
                            Label("Open", systemImage: "arrow.up.right.square")
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }

            if let quote = item.text, !quote.isEmpty {
                Section {
                    Text(quote)
                        .italic(item.anchor != nil)
                        .textSelection(.enabled)
                } header: {
                    if item.anchor == nil { Text("Text") } else { Text("Highlight") }
                }
            }

            if let description = item.imageDescription, !description.isEmpty {
                Section("In the Picture") {
                    Text(description)
                }
            }

            Section("Why You Saved It") {
                IntentPicker(selection: Binding(
                    get: { item.intent },
                    set: { intent in
                        let (items, id) = (services.items, item.id)
                        Task { try? await items.setIntent(intent, forItem: id) }
                    }
                ))
                if item.intent == nil, let suggested = item.suggestedIntent {
                    Text("Looks like: \(Text(suggested.title))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = item.note, !note.isEmpty {
                    Text(note)
                }
            }

            if !item.dates.isEmpty || !item.places.isEmpty {
                Section("Dates and Places") {
                    ForEach(item.dates, id: \.self) { date in
                        Label(
                            date.date.formatted(date: .abbreviated, time: date.hasTime ? .shortened : .omitted),
                            systemImage: date.role == .deadline || date.role == .expiry ? "hourglass" : "calendar"
                        )
                    }
                    ForEach(item.places, id: \.self) { place in
                        Label([place.name, place.address].compactMap { $0 }.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                    }
                }
            }

            Section("Groups") {
                ForEach(context.groups) { group in
                    NavigationLink(value: GroupLink(id: group.id)) {
                        GroupLabel(group: group)
                    }
                }
                Button("Add to Group…", systemImage: "plus") { showsAddToGroup = true }
            }

            Section("Actions") {
                ForEach(context.actions) { action in
                    ActionRow(action: action) { toggle(action) }
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    SuggestedActionRow(suggestion: suggestion) {
                        let repository = services.actions
                        Task { _ = try? await repository.accept(suggestion) }
                    } onDismiss: {
                        let repository = services.actions
                        Task { try? await repository.dismiss(suggestion) }
                    }
                }
                TextField("Add an action", text: $newAction)
                    .onSubmit { addAction() }
                    .submitLabel(.done)
            }
        }
        .navigationTitle(item.displayTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if item.status == .done {
                    Button("Mark as Not Done", systemImage: "arrow.uturn.backward") { setStatus(.active) }
                } else {
                    Button("Mark as Done", systemImage: "checkmark.circle") { setStatus(.done) }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                if item.status == .trashed {
                    Button("Restore", systemImage: "arrow.uturn.backward") { setStatus(.active) }
                } else {
                    Button("Move to Trash", systemImage: "trash", role: .destructive) { setStatus(.trashed) }
                }
            }
        }
        .sheet(isPresented: $showsAddToGroup) {
            AddToGroupSheet(itemIDs: [item.id], services: services)
        }
        .alert("All Actions Done", isPresented: $showsDonePrompt) {
            Button("Mark as Done") { setStatus(.done) }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Mark “\(item.displayTitle)” as done too?")
        }
    }

    private func addAction() {
        let title = newAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newAction = ""
        let (repository, id) = (services.actions, itemID)
        Task { _ = try? await repository.add(title: title, itemID: id) }
    }

    private func toggle(_ action: ActionRecord) {
        let (repository, id) = (services.actions, itemID)
        Task {
            let completion = try? await repository.setDone(action.status != .done, forAction: action.id)
            if completion?.finishedItemID == id { showsDonePrompt = true }
        }
    }

    private func setStatus(_ status: ItemStatus) {
        let (items, id) = (services.items, itemID)
        Task { try? await items.setStatus(status, forItem: id) }
    }
}

extension ItemRecord {
    /// The text-fragment or message link that returns to the exact place (PRD F5).
    var anchorURL: URL? {
        switch anchor {
        case .web(let url, _): url
        case .mail(let url): url
        default: nil
        }
    }
}
