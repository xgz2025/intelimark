//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

#if canImport(FoundationModels)
import Foundation
import FoundationModels
import Model

/// Writes a group's Brief with the on-device model (PRD G3, Docs/architecture.md
/// §6.2). Dated next steps come from the items' own dates (`ActionSuggester`); the
/// model adds undated ones, so it can never invent a deadline.
public struct FoundationModelsBriefWriter: GroupBriefWriter {
    static let instructions = """
        You help a person act on a group of things they saved: web pages, places, products, events, notes.
        Summarize what the items have in common and where things stand. Be concrete and brief.
        Use only the information given. Never invent prices, dates, places or names.
        Write in the language of the items.
        """
    static let retryBudgetScale = 0.4

    public init() {}

    public func brief(for input: BriefInput) async throws -> GroupBrief {
        do {
            return try await generate(input, budgetScale: 1)
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            return try await generate(input, budgetScale: Self.retryBudgetScale)
        }
    }

    private func generate(_ input: BriefInput, budgetScale: Double) async throws -> GroupBrief {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: input.promptText(budgetScale: budgetScale),
            generating: GeneratedBrief.self
        )
        let generated = response.content
        let now = Date()
        let dated = input.items
            .flatMap { ActionSuggester.suggestions(for: $0, now: now) }
            .filter { $0.dueAt != nil }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(2)
        var actions = Array(dated)
        for title in generated.suggestedActions.map(\.trimmed) where !title.isEmpty && actions.count < 4 {
            if !actions.contains(where: { $0.title.lowercased() == title.lowercased() }) {
                actions.append(SuggestedAction(title: title))
            }
        }
        return GroupBrief(
            title: generated.title.trimmed,
            overview: generated.overview.trimmed,
            keyPoints: generated.keyPoints.map(\.trimmed).filter { !$0.isEmpty },
            openQuestions: generated.openQuestions.map(\.trimmed).filter { !$0.isEmpty },
            suggestedActions: actions,
            producer: "foundation-models",
            isProvisional: false
        )
    }
}

@Generable
struct GeneratedBrief {
    @Guide(description: "A short name for the group, at most 5 words")
    var title: String

    @Guide(description: "Two or three sentences: what these items have in common and where things stand")
    var overview: String

    @Guide(description: "The most useful facts across the items, such as prices, dates, places and differences", .maximumCount(5))
    var keyPoints: [String]

    @Guide(description: "Questions the person still needs to answer before acting", .maximumCount(3))
    var openQuestions: [String]

    @Guide(description: "Concrete next steps, each starting with a verb and at most 8 words", .maximumCount(4))
    var suggestedActions: [String]
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
