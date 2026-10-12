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
import Model

/// What a brief is written from: the group's own words and its members' digests,
/// newest first.
public struct BriefInput: Sendable, Equatable {
    public var title: String?
    public var goal: String?
    public var targetDate: Date?
    public var items: [ItemDigest]

    public init(title: String? = nil, goal: String? = nil, targetDate: Date? = nil, items: [ItemDigest]) {
        self.title = title
        self.goal = goal
        self.targetDate = targetDate
        self.items = items
    }

    /// Token budgets (Docs/architecture.md §6.2): about 60 tokens per item, and room
    /// for the instructions and the answer inside the 8,192-token context.
    static let tokensPerItem = 60
    static let itemBudget = 3_600

    /// The prompt: the group, then one line per item until the budget runs out.
    func promptText(budgetScale: Double = 1, now: Date = Date()) -> String {
        var lines = [String]()
        if let title, !title.isEmpty { lines.append("Group: \(title)") }
        if let goal, !goal.isEmpty { lines.append("Goal: \(goal)") }
        if let targetDate { lines.append("Target date: \(targetDate.formatted(date: .abbreviated, time: .omitted))") }
        lines.append("Today: \(now.formatted(date: .abbreviated, time: .omitted))")
        lines.append("Saved items (\(items.count)):")
        var remaining = Int(Double(Self.itemBudget) * budgetScale)
        var included = 0
        for item in items {
            let line = TokenBudget.truncate("- " + Self.describe(item), to: Self.tokensPerItem)
            let cost = TokenBudget.estimate(line)
            guard cost <= remaining else { break }
            lines.append(line)
            remaining -= cost
            included += 1
        }
        if included < items.count {
            lines.append("(\(items.count - included) more items not shown)")
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ item: ItemDigest) -> String {
        var parts = [item.title]
        if let kind = item.kind { parts[0] = "[\(kind.rawValue)] " + item.title }
        if let summary = item.summary, !summary.isEmpty { parts.append(summary) }
        parts += item.facts
        parts += item.dates.prefix(2).map { "\($0.role.rawValue): \($0.date.formatted(date: .abbreviated, time: $0.hasTime ? .shortened : .omitted))" }
        parts += item.places.prefix(1).map { "Place: \($0.name)" }
        if let intent = item.intent { parts.append("Saved to: \(intent.rawValue)") }
        if let note = item.note, !note.isEmpty { parts.append("Note: \(note)") }
        return parts.joined(separator: " — ")
    }
}

/// Writes a group's Brief (PRD G3, Docs/architecture.md §6.1).
public protocol GroupBriefWriter: Sendable {
    func brief(for input: BriefInput) async throws -> GroupBrief
}

/// The brief without a language model: a topic name, what the group contains, the
/// dates and prices that stand out, and rule-based next steps. Provisional: it is
/// rewritten once the on-device model is available.
public struct HeuristicBriefWriter: GroupBriefWriter {
    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func brief(for input: BriefInput) async throws -> GroupBrief {
        let now = self.now()
        let items = input.items
        let title = input.title?.nilIfEmpty ?? TopicNamer.topic(of: items) ?? String(localized: "Saved items")

        let names = items.prefix(3).map { ActionSuggester.shortTitle($0.title) }
        let overview: String
        switch items.count {
        case 0: overview = String(localized: "No items yet.")
        case 1...3: overview = String(localized: "Includes \(names.formatted(.list(type: .and))).")
        default: overview = String(localized: "Includes \(names.formatted(.list(type: .and))) and \(items.count - names.count) more.")
        }

        var keyPoints: [String] = []
        let upcoming = items
            .flatMap { item in item.dates.filter { $0.date > now }.map { (item, $0) } }
            .sorted { $0.1.date < $1.1.date }
        for (item, date) in upcoming.prefix(3) {
            let when = date.date.formatted(date: .abbreviated, time: date.hasTime ? .shortened : .omitted)
            keyPoints.append("\(ActionSuggester.shortTitle(item.title)): \(when)")
        }
        for item in items where keyPoints.count < 5 {
            if let price = item.facts.first(where: { $0.hasPrefix("Price:") }) {
                keyPoints.append("\(ActionSuggester.shortTitle(item.title)): \(price.dropFirst("Price:".count).trimmingCharacters(in: .whitespaces))")
            }
        }

        var openQuestions: [String] = []
        let choices = items.filter { $0.kind == .product || $0.intent == .decide }
        if choices.count >= 2 {
            openQuestions.append(String(localized: "Which one is the best fit?"))
        }

        var actions = items.flatMap { ActionSuggester.suggestions(for: $0, now: now) }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        if choices.count >= 2 {
            actions.insert(SuggestedAction(title: String(localized: "Compare and decide")), at: 0)
        }
        return GroupBrief(
            title: title,
            overview: overview,
            keyPoints: Array(keyPoints.prefix(5)),
            openQuestions: openQuestions,
            suggestedActions: Array(actions.prefix(4)),
            producer: "heuristic",
            isProvisional: true
        )
    }
}

/// Uses the on-device model when it is available, and the heuristic otherwise or
/// when the model fails; checked per brief, like `AdaptiveUnderstander`.
public struct AdaptiveBriefWriter: GroupBriefWriter {
    let primary: any GroupBriefWriter
    let fallback: any GroupBriefWriter
    let isPrimaryAvailable: @Sendable () -> Bool

    public init(primary: any GroupBriefWriter, fallback: any GroupBriefWriter, isPrimaryAvailable: @escaping @Sendable () -> Bool) {
        self.primary = primary
        self.fallback = fallback
        self.isPrimaryAvailable = isPrimaryAvailable
    }

    public func brief(for input: BriefInput) async throws -> GroupBrief {
        guard isPrimaryAvailable() else { return try await fallback.brief(for: input) }
        do {
            return try await primary.brief(for: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.brief(for: input)
        }
    }
}

extension IntelligenceRouter {
    /// The brief writer for this device: the on-device model when Apple
    /// Intelligence is available, the heuristic otherwise.
    public static func makeBriefWriter() -> any GroupBriefWriter {
        #if canImport(FoundationModels)
        return AdaptiveBriefWriter(
            primary: FoundationModelsBriefWriter(),
            fallback: HeuristicBriefWriter(),
            isPrimaryAvailable: { IntelligenceStatus.current == .available }
        )
        #else
        return HeuristicBriefWriter()
        #endif
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
