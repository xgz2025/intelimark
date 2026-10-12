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
import Testing
import Model
@testable import Intelligence

struct ActionSuggesterTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    var nextWeek: Date { now.addingTimeInterval(7 * 86_400) }

    func date(_ date: Date, _ role: ItemDate.Role) -> ItemDate {
        ItemDate(date: date, hasTime: false, role: role, evidence: nil, source: .structured)
    }

    @Test func buyingUsesTheDeadline() {
        let item = ItemDigest(id: "1", title: "Aeron Chair", kind: .product, intent: .buy, dates: [date(nextWeek, .expiry)])
        #expect(ActionSuggester.suggestions(for: item, now: now) == [SuggestedAction(title: "Buy Aeron Chair", dueAt: nextWeek, itemID: "1")])
    }

    @Test func eventsAreDueWhenTheyStart() {
        let item = ItemDigest(id: "2", title: "Autumn concert", kind: .event, intent: .go, dates: [date(nextWeek, .eventStart)])
        #expect(ActionSuggester.suggestions(for: item, now: now).map(\.title) == ["Go to Autumn concert"])
        #expect(ActionSuggester.suggestions(for: item, now: now).first?.dueAt == nextWeek)
    }

    @Test func pastDatesAreIgnored() {
        let item = ItemDigest(id: "3", title: "Old sale", kind: .product, intent: .buy, dates: [date(now.addingTimeInterval(-86_400), .deadline)])
        #expect(ActionSuggester.suggestions(for: item, now: now).first?.dueAt == nil)
    }

    @Test func recipesAreCookedAndArticlesRead() {
        let recipe = ItemDigest(id: "4", title: "Miso ramen", kind: .recipe, intent: .tryIt)
        let article = ItemDigest(id: "5", title: "Why sleep matters", kind: .article, intent: .read)
        #expect(ActionSuggester.suggestions(for: recipe, now: now).map(\.title) == ["Cook Miso ramen"])
        #expect(ActionSuggester.suggestions(for: article, now: now).map(\.title) == ["Read Why sleep matters"])
        #expect(ActionSuggester.suggestions(for: ItemDigest(id: "6", title: "A quote", intent: .reference), now: now).isEmpty)
    }

    @Test func longTitlesAreShortenedAtAWord() {
        let title = String(repeating: "word ", count: 20)
        let short = ActionSuggester.shortTitle(title)
        #expect(short.count <= ActionSuggester.maximumTitleLength + 1)
        #expect(short.hasSuffix("word…"))
    }
}

struct TopicNamerTests {
    @Test func usesTheKeywordMostItemsShare() {
        let items = [
            ItemDigest(id: "1", title: "Ichiran Ramen", keywords: ["kyoto", "ramen"]),
            ItemDigest(id: "2", title: "Kinkaku-ji", keywords: ["Kyoto", "temple"]),
            ItemDigest(id: "3", title: "Ryokan list", keywords: ["Kyoto", "hotel"]),
        ]
        #expect(TopicNamer.topic(of: items) == "Kyoto")
    }

    @Test func fallsBackToSharedTitleWords() {
        let items = [
            ItemDigest(id: "1", title: "Standing desk review"),
            ItemDigest(id: "2", title: "Desk lamp ideas"),
            ItemDigest(id: "3", title: "Monitor arm for a desk"),
        ]
        #expect(TopicNamer.topic(of: items) == "Desk")
    }

    @Test func noSharedTopicGivesNoName() {
        let items = [ItemDigest(id: "1", title: "Apples"), ItemDigest(id: "2", title: "Bridges"), ItemDigest(id: "3", title: "Clouds")]
        #expect(TopicNamer.topic(of: items) == nil)
    }
}

struct HeuristicBriefWriterTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func summarizesWhatTheGroupHolds() async throws {
        let concert = ItemDigest(
            id: "1", title: "Autumn concert", kind: .event, intent: .go, keywords: ["kyoto"],
            dates: [ItemDate(date: now.addingTimeInterval(3 * 86_400), hasTime: false, role: .eventStart, evidence: nil, source: .structured)]
        )
        let chairA = ItemDigest(id: "2", title: "Aeron", kind: .product, intent: .buy, facts: ["Price: 1,395 USD"], keywords: ["kyoto"])
        let chairB = ItemDigest(id: "3", title: "Leap", kind: .product, intent: .buy, facts: ["Price: 1,099 USD"])
        let writer = HeuristicBriefWriter { now }

        let brief = try await writer.brief(for: BriefInput(items: [concert, chairA, chairB]))
        #expect(brief.title == "Kyoto")
        #expect(["Autumn concert", "Aeron", "Leap"].allSatisfy { brief.overview.contains($0) })
        #expect(brief.keyPoints.first?.hasPrefix("Autumn concert: ") == true)
        #expect(brief.keyPoints.contains("Aeron: 1,395 USD"))
        #expect(brief.openQuestions == ["Which one is the best fit?"])
        #expect(brief.suggestedActions.first?.title == "Compare and decide")
        #expect(brief.suggestedActions.contains { $0.title == "Go to Autumn concert" })
        #expect(brief.isProvisional)
    }

    @Test func theUsersTitleWins() async throws {
        let brief = try await HeuristicBriefWriter { now }.brief(for: BriefInput(title: "Desk setup", items: []))
        #expect(brief.title == "Desk setup")
        #expect(brief.overview == "No items yet.")
    }

    @Test func promptsStayWithinTheBudget() {
        let items = (0..<200).map { ItemDigest(id: "\($0)", title: "Item \($0) " + String(repeating: "detail ", count: 40)) }
        let prompt = BriefInput(title: "Big group", items: items).promptText(now: now)
        #expect(TokenBudget.estimate(prompt) < BriefInput.itemBudget + 200)
        #expect(prompt.contains("more items not shown"))
        #expect(prompt.hasPrefix("Group: Big group"))
    }
}
