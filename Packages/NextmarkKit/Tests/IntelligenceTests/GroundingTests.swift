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

struct TokenBudgetTests {
    @Test func countsCJKCharactersAsWholeTokens() {
        #expect(TokenBudget.estimate("abcdef") == 2)
        #expect(TokenBudget.estimate("京都") == 2)
        #expect(TokenBudget.estimate("한국어") == 3)
    }

    @Test func truncatesToTheBudget() {
        #expect(TokenBudget.truncate("京都の紅葉", to: 3) == "京都の")
        #expect(TokenBudget.truncate("abcdefghi", to: 2) == "abcdef")
        #expect(TokenBudget.truncate("short", to: 100) == "short")
        #expect(TokenBudget.truncate("anything", to: 0) == "")
    }
}

struct DateFinderTests {
    @Test func detectsDatesAndWhetherATimeWasGiven() throws {
        let matches = DateFinder.matches(in: "Doors open Nov 21, 2026 at 7:30 PM. Refunds until November 1, 2026.")
        #expect(matches.count == 2)
        #expect(matches.first?.hasTime == true)
        #expect(matches.first?.isUntil == false)
        #expect(matches.last?.hasTime == false)
    }

    @Test func openEndedRangesResolveToTheirEnd() throws {
        // NSDataDetector returns "until …" as a range starting now; the named date is its end.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let match = try #require(DateFinder.matches(in: "Refunds until November 1, 2026.").first)
        let parts = calendar.dateComponents([.year, .month, .day], from: match.date)
        #expect(match.isUntil)
        #expect([parts.year, parts.month, parts.day] == [2026, 11, 1])
    }

    @Test func openEndedStartsAreNowOrNoonToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 22, minute: 5)))
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9)))
        let tomorrowNoon = noon.addingTimeInterval(86_400)
        #expect(DateFinder.isOpenEndedStart(now.addingTimeInterval(-5), now: now, calendar: calendar))
        #expect(DateFinder.isOpenEndedStart(noon, now: now, calendar: calendar))
        #expect(!DateFinder.isOpenEndedStart(morning, now: now, calendar: calendar))
        #expect(!DateFinder.isOpenEndedStart(tomorrowNoon, now: now, calendar: calendar))
    }

    @Test(arguments: ["7:30", "7pm", "19時", "下午3点", "3 p.m."])
    func recognizesTimesOfDay(text: String) {
        #expect(DateFinder.mentionsTimeOfDay(text))
    }

    @Test(arguments: [
        ("11:59 PM", false), ("at 7pm", false), ("19時", false),
        ("Oct 31 at 7pm", true), ("tomorrow at 9:00", true), ("明天下午3点", true), ("Friday", true),
    ])
    func distinguishesDaysFromBareTimes(text: String, mentionsDay: Bool) {
        #expect(DateFinder.mentionsDay(text) == mentionsDay)
    }
}

struct GroundingTests {
    let source = "Autumn concert at Budokan, Sat, Nov 21, 2026 at 7:30 PM. Doors open at 6 PM. 2-3 Kitanomaru Koen, Tokyo."
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    @Test func keepsDatesQuotedFromTheSource() throws {
        let dates = Grounding.dates(
            from: [DateCandidate(evidence: "Sat, Nov 21, 2026 at 7:30 PM", isoDate: "2026-11-21T19:30", role: .eventStart)],
            in: source
        )
        let date = try #require(dates.first)
        #expect(date.role == .eventStart)
        #expect(date.hasTime)
        #expect(date.source == .model)
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date.date)
        #expect([parts.month, parts.day, parts.hour, parts.minute] == [11, 21, 19, 30])
    }

    @Test func dropsInventedEvidence() {
        let dates = Grounding.dates(
            from: [DateCandidate(evidence: "Dec 25", isoDate: "2026-12-25", role: .deadline)],
            in: source
        )
        #expect(dates.isEmpty)
    }

    @Test func dropsDatesThatDisagreeWithTheirEvidence() {
        let dates = Grounding.dates(
            from: [DateCandidate(evidence: "Nov 21, 2026", isoDate: "2026-11-22", role: .eventStart)],
            in: source
        )
        #expect(dates.isEmpty)
    }

    @Test func dropsUnparseableDates() {
        let dates = Grounding.dates(
            from: [DateCandidate(evidence: "Nov 21, 2026", isoDate: "next Saturday", role: .eventStart)],
            in: source
        )
        #expect(dates.isEmpty)
    }

    @Test func keepsPlacesNamedInTheSource() {
        let places = Grounding.places(
            from: [
                PlaceCandidate(name: "Budokan", address: "2-3 Kitanomaru Koen, Tokyo"),
                PlaceCandidate(name: "Tokyo Dome", address: ""),
                PlaceCandidate(name: "budokan", address: ""),
            ],
            in: source
        )
        #expect(places == [ItemPlace(name: "Budokan", address: "2-3 Kitanomaru Koen, Tokyo", source: .model)])
    }

    @Test func dropsAddressesNotInTheSource() {
        let places = Grounding.places(from: [PlaceCandidate(name: "Budokan", address: "1 Main St")], in: source)
        #expect(places.first?.address == nil)
    }
}

struct AdaptiveUnderstanderTests {
    struct Fixed: ItemUnderstander {
        let producer: String
        func understand(_ input: UnderstandingInput) async throws -> Understanding {
            Understanding(title: producer, summary: "", semanticKind: .other, likelyIntent: nil, keywords: [], producer: producer)
        }
    }

    struct Failing: ItemUnderstander {
        func understand(_ input: UnderstandingInput) async throws -> Understanding {
            throw URLError(.unknown)
        }
    }

    @Test func usesThePrimaryWhenAvailable() async throws {
        let understander = AdaptiveUnderstander(primary: Fixed(producer: "model"), fallback: Fixed(producer: "heuristic")) { true }
        #expect(try await understander.understand(UnderstandingInput()).producer == "model")
    }

    @Test func usesTheFallbackWhenUnavailable() async throws {
        let understander = AdaptiveUnderstander(primary: Fixed(producer: "model"), fallback: Fixed(producer: "heuristic")) { false }
        #expect(try await understander.understand(UnderstandingInput()).producer == "heuristic")
    }

    @Test func fallsBackWhenThePrimaryFails() async throws {
        let understander = AdaptiveUnderstander(primary: Failing(), fallback: Fixed(producer: "heuristic")) { true }
        #expect(try await understander.understand(UnderstandingInput()).producer == "heuristic")
    }
}
