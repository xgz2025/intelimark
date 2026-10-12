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

struct HeuristicUnderstanderTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=1", SemanticKind.video),
        ("https://maps.apple.com/?q=ramen", .place),
        ("https://www.google.com/maps/place/x", .place),
        ("https://www.amazon.com/dp/B000", .product),
        ("https://example.com/paper.pdf", .document),
        ("https://example.com/blog/post", .article),
    ])
    func guessesKindFromURL(url: String, expected: SemanticKind) {
        #expect(HeuristicUnderstander.kind(for: UnderstandingInput(url: URL(string: url))) == expected)
    }

    @Test func fallsBackToFirstLineThenHost() {
        #expect(HeuristicUnderstander.title(for: UnderstandingInput(text: "First line\nSecond")) == "First line")
        #expect(HeuristicUnderstander.title(for: UnderstandingInput(url: URL(string: "https://example.com/x"))) == "example.com")
        // Nothing to go on (a scanned PDF): no title, so the captured one is kept.
        #expect(HeuristicUnderstander.title(for: UnderstandingInput(kind: .pdf)).isEmpty)
    }

    @Test func keywordsAreFrequentNonStopwords() {
        let input = UnderstandingInput(title: "Ramen ramen guide", text: "The best ramen shops with late hours in Kyoto. Kyoto ramen.")
        #expect(Array(HeuristicUnderstander.keywords(for: input).prefix(2)) == ["ramen", "kyoto"])
    }

    @Test func promptFitsTheTokenBudget() {
        let latin = UnderstandingInput(text: String(repeating: "word ", count: 4_000))
        #expect(TokenBudget.estimate(latin.promptText) <= UnderstandingInput.contentTokenBudget + 10)

        // CJK text is about one token per character: 10,000 characters must be cut far shorter.
        let japanese = UnderstandingInput(text: String(repeating: "京都の紅葉", count: 2_000))
        #expect(TokenBudget.estimate(japanese.promptText) <= UnderstandingInput.contentTokenBudget + 10)
        #expect(japanese.promptText.count < 2_500)
    }

    @Test func promptCarriesTheSavedDateAndKind() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let saved = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        let prompt = UnderstandingInput(title: "Ticket", kind: .image, capturedAt: saved).promptText
        #expect(prompt.contains("Saved on: 2026-10-09 (Friday)"))
        #expect(prompt.contains("Item type: photo or screenshot"))
    }

    @Test func findsUpcomingDatesButNotPastOnes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let saved = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9))!
        let input = UnderstandingInput(
            text: "Published January 2, 2020. The sale ends October 31, 2026 at 11:59 PM.",
            capturedAt: saved
        )
        let dates = HeuristicUnderstander.dates(for: input)
        let detected = DateFinder.matches(in: input.groundingText).map { "\($0.text) → \($0.date)" }
        let date = try #require(dates.first, "detector matches: \(detected)")
        #expect(dates.count == 1, "detector matches: \(detected)")
        let parts = calendar.dateComponents([.year, .month, .day], from: date.date)
        #expect([parts.year, parts.month, parts.day] == [2026, 10, 31], "detector matches: \(detected)")
        #expect(date.hasTime)
        #expect(date.role == .deadline)    // "ends …" is a deadline
        #expect(date.source == .detector)
    }

    @Test func describesImagesFromLabelsAndText() {
        let input = UnderstandingInput(ocrText: "\nLunch special 980 yen\nMiso ramen", imageLabels: ["food", "bowl"], kind: .image)
        #expect(HeuristicUnderstander.imageDescription(for: input) == "food, bowl — “Lunch special 980 yen”")
        #expect(HeuristicUnderstander.imageDescription(for: UnderstandingInput(ocrText: "x", kind: .link)) == nil)
    }

    @Test func heuristicResultsAreProvisional() async throws {
        let understanding = try await HeuristicUnderstander().understand(UnderstandingInput(title: "Note"))
        #expect(understanding.isProvisional)
    }
}
