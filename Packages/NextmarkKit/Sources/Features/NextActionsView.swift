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

/// Every open action, by when it's due (PRD A4), plus suggested next steps from
/// recent saves (A2).
struct NextActionsView: View {
    let services: LibraryServices
    @State private var actions: [ActionContext] = []
    @State private var suggestions: [SuggestedAction] = []
    @State private var newAction = ""
    @State private var finishedItem: FinishedItem?
    @State private var showsFinishedPrompt = false
    /// Set once the person has answered the prompt: a good moment to ask for a rating.
    @State private var answeredFinishedPrompt = false

    private struct FinishedItem: Identifiable {
        let id: String
        let title: String
    }

    private enum Bucket: CaseIterable {
        case overdue, today, upcoming, anytime

        var title: LocalizedStringKey {
            switch self {
            case .overdue: "Overdue"
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .anytime: "Anytime"
            }
        }

        static func of(_ due: Date?, now: Date, calendar: Calendar) -> Bucket {
            guard let due else { return .anytime }
            let today = calendar.startOfDay(for: now)
            if due < today { return .overdue }
            if calendar.isDate(due, inSameDayAs: now) { return .today }
            return .upcoming
        }
    }

    var body: some View {
        let now = Date()
        let buckets = Dictionary(grouping: actions) { Bucket.of($0.action.dueAt, now: now, calendar: .current) }
        List {
            Section {
                TextField("New action", text: $newAction)
                    .onSubmit { addAction() }
                    .submitLabel(.done)
            }
            ForEach(Bucket.allCases, id: \.self) { bucket in
                if let contexts = buckets[bucket], !contexts.isEmpty {
                    Section(bucket.title) {
                        ForEach(contexts) { context in
                            actionRow(context)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(context) }
                                }
                                .contextMenu {
                                    Button("Delete Action", systemImage: "trash", role: .destructive) { delete(context) }
                                }
                        }
                    }
                }
            }
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.self) { suggestion in
                        SuggestedActionRow(suggestion: suggestion) {
                            accept(suggestion)
                        } onDismiss: {
                            dismissSuggestion(suggestion)
                        }
                    }
                } header: {
                    Text("Suggested from Recent Saves")
                }
            }
        }
        .overlay {
            if actions.isEmpty && suggestions.isEmpty {
                ContentUnavailableView(
                    "Nothing to Do", systemImage: "checklist",
                    description: Text("Actions you add to items and groups appear here, earliest first.")
                )
            }
        }
        .navigationTitle("Next Actions")
        .task {
            for await value in services.actions.nextActions().ignoringErrors() {
                actions = value
                await loadSuggestions()
            }
        }
        // Every action on a save done is a good moment to ask for a rating, once the
        // question about the item has been answered.
        .requestsReview(after: answeredFinishedPrompt)
        .alert("All Actions Done", isPresented: $showsFinishedPrompt, presenting: finishedItem) { item in
            Button("Mark Item as Done") {
                let (items, id) = (services.items, item.id)
                performEdit { try await items.setStatus(.done, forItem: id) }
                answeredFinishedPrompt = true
            }
            Button("Keep in Inbox", role: .cancel) { answeredFinishedPrompt = true }
        } message: { item in
            Text("You've finished every action for “\(item.title)”. Mark the item as done too? It moves from the Inbox to Done.")
        }
    }

    /// Leads to what the action is for: its group, or the item it was added to.
    @ViewBuilder
    private func actionRow(_ context: ActionContext) -> some View {
        let row = ActionRow(action: context.action, context: contextLabel(context)) {
            complete(context.action)
        }
        if let groupID = context.action.groupID {
            NavigationLink(value: GroupLink(id: groupID)) { row }
        } else if let itemID = context.action.itemID {
            NavigationLink(value: ItemLink(id: itemID)) { row }
        } else {
            row
        }
    }

    private func delete(_ context: ActionContext) {
        let (repository, id) = (services.actions, context.action.id)
        performEdit { try await repository.delete(id) }
    }

    private func contextLabel(_ context: ActionContext) -> String? {
        if let group = context.groupTitle {
            return [context.groupEmoji, group].compactMap { $0 }.joined(separator: " ")
        }
        return context.itemTitle
    }

    private func addAction() {
        let title = newAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newAction = ""
        let repository = services.actions
        performEdit { _ = try await repository.add(title: title) }
    }

    private func complete(_ action: ActionRecord) {
        let (repository, items) = (services.actions, services.items)
        performEdit {
            let completion = try await repository.setDone(true, forAction: action.id)
            if let itemID = completion.finishedItemID, let item = try? await items.item(id: itemID) {
                finishedItem = FinishedItem(id: itemID, title: item.displayTitle)
                answeredFinishedPrompt = false
                showsFinishedPrompt = true
            }
        }
    }

    private func accept(_ suggestion: SuggestedAction) {
        suggestions.removeAll { $0 == suggestion }
        let repository = services.actions
        performEdit { _ = try await repository.accept(suggestion) }
    }

    private func dismissSuggestion(_ suggestion: SuggestedAction) {
        suggestions.removeAll { $0 == suggestion }
        let repository = services.actions
        performEdit { try await repository.dismiss(suggestion) }
    }

    /// Next steps for the newest saves that have no actions of that name yet.
    private func loadSuggestions() async {
        guard let recent = try? await services.items.recentItems(limit: 30) else { return }
        let known = (try? await services.actions.knownTitles(itemIDs: recent.map(\.id))) ?? []
        let now = Date()
        suggestions = Array(
            recent
                .flatMap { ActionSuggester.suggestions(for: $0.digest, now: now) }
                .filter { !known.contains($0.title.lowercased()) }
                .prefix(5)
        )
    }
}
