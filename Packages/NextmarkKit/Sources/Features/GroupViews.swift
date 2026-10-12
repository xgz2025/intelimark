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
import Store
import DesignSystem

/// A group: its Brief, next steps, actions and items (PRD G1–G3, G6, A1, A2, A5).
struct GroupDetailView: View {
    let groupID: String
    let services: LibraryServices
    @State private var detail: GroupDetail?
    @State private var newAction = ""
    @State private var showsRename = false
    @State private var showsPlan = false
    @State private var showsDeleteConfirmation = false
    @State private var showsDonePrompt = false
    @State private var outcome = ""
    @State private var showsPaywall = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ProAccess.self) private var pro: ProAccess?

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else {
                ProgressView()
            }
        }
        .task(id: groupID) {
            for await value in services.groups.detail(id: groupID).ignoringErrors() {
                detail = value
            }
        }
    }

    private func content(_ detail: GroupDetail) -> some View {
        let group = detail.group
        let confirmed = detail.members.filter { $0.membership.locked }
        let suggested = detail.members.filter { $0.membership.isSuggested }
        let isPro = pro?.isPro ?? false
        // Next steps come from the Brief, a Pro feature.
        let suggestions = (isPro ? group.brief?.suggestedActions ?? [] : [])
            .filter { !detail.knownActionTitles.contains($0.title.lowercased()) }
        return List {
            Section {
                GroupHeader(group: group, memberCount: confirmed.count)
            }

            if group.state == .suggested {
                Section {
                    Text("Nextmark found \(suggested.count) saves that seem to belong together.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Keep Group", systemImage: "checkmark") { keep() }
                            .buttonStyle(.borderedProminent)
                        Button("Dismiss", systemImage: "xmark") {
                            run { try await services.groups.dismissSuggestion(groupID) }
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            BriefSection(group: group, hasMembers: !confirmed.isEmpty, isPro: isPro) {
                run {
                    try await services.groups.requestBrief(groupID)
                    await services.refresh()
                }
            }

            if !suggestions.isEmpty && group.status == .active {
                Section("Suggested Next Steps") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        SuggestedActionRow(suggestion: suggestion) {
                            run { _ = try await services.actions.accept(suggestion, groupID: groupID) }
                        } onDismiss: {
                            run { try await services.actions.dismiss(suggestion, groupID: groupID) }
                        }
                    }
                }
            }

            Section("Actions") {
                ForEach(detail.actions) { action in
                    ActionRow(action: action) { toggle(action) }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                run { try await services.actions.delete(action.id) }
                            }
                        }
                }
                TextField("Add an action", text: $newAction)
                    .onSubmit { addAction() }
                    .submitLabel(.done)
            }

            if !suggested.isEmpty && group.state == .accepted {
                Section {
                    ForEach(suggested) { member in
                        HStack {
                            ItemLinkRow(item: member.item, services: services)
                            Button("Keep", systemImage: "checkmark.circle") {
                                run { try await services.groups.confirmItem(member.item.id, in: groupID) }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            Button("Remove", systemImage: "xmark.circle") {
                                run { try await services.groups.removeItem(member.item.id, from: groupID) }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Suggested Items")
                } footer: {
                    Text("New saves that look related. Keep them in the group or remove them.")
                }
            }

            Section {
                ForEach(group.state == .suggested ? suggested : confirmed) { member in
                    ItemLinkRow(item: member.item, services: services)
                        .swipeActions {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                run { try await services.groups.removeItem(member.item.id, from: groupID) }
                            }
                        }
                }
            } header: {
                if group.state == .suggested {
                    Text("Items")
                } else {
                    Text("Items (\(confirmed.count))")
                }
            }
        }
        .navigationTitle(group.displayTitle)
        .dropDestination(for: String.self) { ids, _ in
            run { _ = try await services.groups.addItems(ids, to: groupID) }
            return true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename…", systemImage: "pencil") { showsRename = true }
                    if group.isPlan {
                        Button("Edit Plan…", systemImage: "calendar.badge.clock") { showsPlan = true }
                    } else {
                        Button("Make a Plan…", systemImage: "calendar.badge.clock") { showsPlan = true }
                    }
                    Button("Write Brief Again", systemImage: "arrow.clockwise") {
                        run {
                            try await services.groups.requestBrief(groupID)
                            await services.refresh()
                        }
                    }
                    Divider()
                    if group.status == .done {
                        Button("Reopen", systemImage: "arrow.uturn.backward") {
                            run { try await services.groups.setStatus(.active, forGroup: groupID) }
                        }
                    } else {
                        Button("Mark as Done…", systemImage: "checkmark.circle") { showsDonePrompt = true }
                    }
                    Divider()
                    Button("Delete Group…", systemImage: "trash", role: .destructive) { showsDeleteConfirmation = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView(reason: "Free keeps \(FreeTier.smartGroups) smart groups. Pro keeps as many as you like.")
        }
        .sheet(isPresented: $showsRename) {
            RenameGroupSheet(group: group, services: services)
        }
        .sheet(isPresented: $showsPlan) {
            PlanSheet(group: group, services: services)
        }
        .confirmationDialog(
            "Delete “\(group.displayTitle)”?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                run { try await services.groups.delete(groupID) }
                dismiss()
            }
        } message: {
            Text("The items stay in your library.")
        }
        .alert("Mark “\(group.displayTitle)” as done?", isPresented: $showsDonePrompt) {
            TextField("What came of it? (optional)", text: $outcome)
            Button("Mark as Done") {
                let note = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
                run { try await services.groups.setStatus(.done, forGroup: groupID, outcome: note.isEmpty ? nil : note) }
                outcome = ""
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Done groups move to the end of the list with their outcome.")
        }
    }

    private func addAction() {
        let title = newAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newAction = ""
        run { _ = try await services.actions.add(title: title, groupID: groupID) }
    }

    private func toggle(_ action: ActionRecord) {
        let (actions, groupID) = (services.actions, groupID)
        Task {
            let completion = try? await actions.setDone(action.status != .done, forAction: action.id)
            if completion?.finishedGroupID == groupID {
                showsDonePrompt = true
            }
        }
    }

    /// Runs an edit; observation updates the screen, so errors only leave it unchanged.
    private func run(_ work: @escaping () async throws -> Void) {
        Task { try? await work() }
    }

    private func keep() {
        let (groups, limit) = (services.groups, pro?.smartGroupLimit ?? FreeTier.smartGroups)
        Task {
            do {
                try await groups.acceptSuggestion(groupID, smartGroupLimit: limit)
            } catch is GroupLimitReached {
                showsPaywall = true
            } catch {}
        }
    }
}

private struct GroupHeader: View {
    let group: GroupRecord
    let memberCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(group.emoji ?? "📁")
                .font(.system(size: 44))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.displayTitle)
                    .font(.title2.bold())
                if group.isPlan {
                    HStack(spacing: 6) {
                        if let goal = group.goal, !goal.isEmpty { Text(goal) }
                        if let date = group.targetDate {
                            Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if group.status == .done {
                    Label("Done", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    if let outcome = group.outcome, !outcome.isEmpty {
                        Text(outcome).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The Brief (PRD G3): overview, key points and open questions.
private struct BriefSection: View {
    let group: GroupRecord
    let hasMembers: Bool
    let isPro: Bool
    let onWriteNow: () -> Void

    var body: some View {
        Section {
            if !isPro {
                Text("An overview of this group, its key points, open questions and next steps.")
                    .foregroundStyle(.secondary)
                ProUpsellRow(text: "Get Briefs with Pro", reason: "Briefs sum up each group for you.")
            } else if let brief = group.brief {
                Text(brief.overview)
                if !brief.keyPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(brief.keyPoints, id: \.self) { point in
                            Label(point, systemImage: "smallcircle.filled.circle")
                                .labelStyle(BulletLabelStyle())
                        }
                    }
                }
                if !brief.openQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Open questions").font(.subheadline.bold())
                        ForEach(brief.openQuestions, id: \.self) { question in
                            Label(question, systemImage: "questionmark.circle")
                        }
                    }
                }
            } else if hasMembers {
                Text("The brief will be written shortly.")
                    .foregroundStyle(.secondary)
                Button("Write Brief Now", systemImage: "sparkles", action: onWriteNow)
            } else {
                Text("Add items to get a brief: an overview, key points and next steps.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Brief")
        } footer: {
            if isPro, let brief = group.brief {
                if brief.isProvisional {
                    Text("A quick summary. It's rewritten with Apple Intelligence when available.")
                } else if let updated = group.briefUpdatedAt {
                    Text("Written with Apple Intelligence \(updated.formatted(.relative(presentation: .named))).")
                }
            }
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

private struct RenameGroupSheet: View {
    let group: GroupRecord
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var emoji = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $title)
                TextField("Emoji", text: $emoji)
            }
            .formStyle(.grouped)
            .navigationTitle("Rename Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let (groups, id, title, emoji) = (services.groups, group.id, title, String(emoji.prefix(2)))
                        Task { try? await groups.rename(id, to: title, emoji: emoji) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                title = group.displayTitle
                emoji = group.emoji ?? ""
            }
        }
        .frame(minWidth: 340, minHeight: 200)
    }
}

/// Turns a group into a plan with a goal and a date (PRD G6).
private struct PlanSheet: View {
    let group: GroupRecord
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var goal = ""
    @State private var hasDate = true
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal", text: $goal, prompt: Text("Trip to Kyoto, Pick a new desk…"))
                Toggle("Date", isOn: $hasDate.animation())
                if hasDate {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }
            }
            .formStyle(.grouped)
            .navigationTitle(group.isPlan ? Text("Edit Plan") : Text("Make a Plan"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let target: Date? = hasDate ? date : nil
                        let (groups, id, goal) = (services.groups, group.id, goal)
                        Task { try? await groups.makePlan(id, goal: goal, targetDate: target) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                goal = group.goal ?? ""
                hasDate = group.targetDate != nil || !group.isPlan
                date = group.targetDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}

/// Groups Nextmark proposes (PRD G2): keep, open, or dismiss each.
struct SuggestionsView: View {
    let services: LibraryServices
    @State private var suggestions: [GroupSummary] = []
    @State private var showsPaywall = false
    @Environment(ProAccess.self) private var pro: ProAccess?

    var body: some View {
        List {
            ForEach(suggestions) { summary in
                NavigationLink(value: GroupLink(id: summary.id)) {
                    GroupLabel(group: summary.group, count: summary.suggestedCount)
                }
                .swipeActions {
                    Button("Dismiss", systemImage: "xmark", role: .destructive) {
                        let (groups, id) = (services.groups, summary.id)
                        Task { try? await groups.dismissSuggestion(id) }
                    }
                    Button("Keep", systemImage: "checkmark") {
                        let (groups, id) = (services.groups, summary.id)
                        let limit = pro?.smartGroupLimit ?? FreeTier.smartGroups
                        Task {
                            do {
                                try await groups.acceptSuggestion(id, smartGroupLimit: limit)
                            } catch is GroupLimitReached {
                                showsPaywall = true
                            } catch {}
                        }
                    }
                    .tint(.green)
                }
            }
        }
        .overlay {
            if suggestions.isEmpty {
                ContentUnavailableView(
                    "No Suggestions", systemImage: "sparkles",
                    description: Text("As you save more, Nextmark proposes groups of related items here.")
                )
            }
        }
        .navigationTitle("Suggested Groups")
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView(reason: "Free keeps \(FreeTier.smartGroups) smart groups. Pro keeps as many as you like.")
        }
        .task {
            for await summaries in services.groups.summaries(states: [.suggested]).ignoringErrors() {
                suggestions = summaries
            }
        }
    }
}

/// Navigates to a group's screen from inside a stack.
struct GroupLink: Hashable {
    let id: String
}
