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
import GRDB
import Model
@testable import Library
@testable import Moments

/// Fixed clock and calendar: Tuesday, Nov 10 2026, noon UTC.
struct MomentClock {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    var now: Date { date(10) }
}

func item(_ title: String, dates: [ItemDate] = [], status: ItemStatus = .inbox, createdAt: Date) -> ItemRecord {
    var item = ItemRecord(envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, title: title), now: createdAt)
    item.createdAt = createdAt
    item.dates = dates
    item.status = status
    return item
}

struct MomentGeneratorTests {
    let clock = MomentClock()
    var generator: MomentGenerator { MomentGenerator(calendar: clock.calendar) }

    func moments(items: [ItemRecord] = [], plans: [GroupSummary] = [], actions: [ActionContext] = [], reviewCount: Int = 0,
                 settings: MomentSettings = MomentSettings(), now: Date? = nil) -> [MomentCandidate] {
        generator.candidates(items: items, plans: plans, actions: actions, reviewCount: reviewCount, settings: settings, now: now ?? clock.now)
    }

    @Test func saleEndsComeBackTheMorningBefore() throws {
        let sale = item("Aeron chair", dates: [ItemDate(date: clock.date(20), hasTime: false, role: .expiry, source: .structured)], createdAt: clock.now)
        let moment = try #require(moments(items: [sale]).first)
        #expect(moment.reason == .expiry)
        #expect(moment.fireDate == clock.date(19, 10))
        #expect(moment.title == "Aeron chair")
        #expect(moment.body.hasPrefix("Ends "))
        #expect(moment.identifier == "moment.expiry.\(sale.id)")
    }

    @Test func eventsComeBackTheEveningBeforeOrHoursBefore() throws {
        let concert = item(
            "Autumn concert", dates: [ItemDate(date: clock.date(21, 19, 30), hasTime: true, role: .eventStart, source: .structured)],
            createdAt: clock.now
        )
        #expect(moments(items: [concert]).first?.fireDate == clock.date(20, 18))
        // Saved after that evening: three hours before it starts.
        #expect(moments(items: [concert], now: clock.date(20, 20)).first?.fireDate == clock.date(21, 16, 30))
    }

    @Test func onlyTheNextUsefulDateCounts() {
        let dates = [
            ItemDate(date: clock.date(1), hasTime: false, role: .deadline, source: .model),        // past
            ItemDate(date: clock.date(12), hasTime: false, role: .mentioned, source: .detector),    // just mentioned
            ItemDate(date: clock.date(25), hasTime: false, role: .deadline, source: .model),
        ]
        let found = moments(items: [item("Grant", dates: dates, createdAt: clock.now)])
        #expect(found.map(\.fireDate) == [clock.date(24, 10)])
        #expect(moments(items: [item("Done", dates: dates, status: .done, createdAt: clock.now)]).isEmpty)
    }

    @Test func aDeadlineStaysRelevantUntilItsDayEnds() {
        let grant = item("Grant", dates: [
            ItemDate(date: clock.date(11, 0), hasTime: false, role: .deadline, source: .model),
            ItemDate(date: clock.date(25, 0), hasTime: false, role: .expiry, source: .model),
        ], createdAt: clock.now)
        let relevant = generator.relevant(
            items: [grant], plans: [], actions: [], reviewCount: 0, settings: MomentSettings(), now: clock.now
        )
        // The morning before tomorrow's deadline has passed, but the deadline still matters.
        #expect(relevant.map(\.reason) == [.deadline, .expiry])
        #expect(relevant.first?.latest == clock.date(12, 0))
        // What gets scheduled is the next date that can still be announced in time.
        #expect(moments(items: [grant]).map(\.fireDate) == [clock.date(24, 10)])
    }

    @Test func plansComeBackFiveDaysAndOneDayBefore() {
        func plan(_ day: Int) -> GroupSummary {
            var group = GroupRecord(kind: .plan, state: .accepted, userTitle: "Kyoto trip", emoji: "🧳", now: clock.now)
            group.targetDate = clock.date(day, 0)
            return GroupSummary(group: group, memberCount: 14, suggestedCount: 0, openActionCount: 3)
        }
        let far = moments(plans: [plan(20)])
        #expect(far.map(\.fireDate) == [clock.date(15, 9)])
        #expect(far.first?.title == "🧳 Kyoto trip")
        #expect(far.first?.body.hasSuffix("14 saves, 3 open actions") == true)
        #expect(moments(plans: [plan(13)]).map(\.fireDate) == [clock.date(12, 9)])
    }

    @Test func actionsAreDueInTheMorning() {
        let due = ActionContext(action: ActionRecord(title: "Book a table", dueAt: clock.date(12, 15)), itemTitle: "Ichiran")
        let today = ActionContext(action: ActionRecord(title: "Too late", dueAt: clock.date(10, 18)))
        let found = moments(actions: [due, today])
        #expect(found.map(\.fireDate) == [clock.date(12, 9)])
        #expect(found.first?.title == "Due today: Book a table")
        #expect(found.first?.body == "Ichiran")
        #expect(found.first?.targetKind == .action)
    }

    @Test func theWeeklyReviewComesOnTheChosenDay() {
        #expect(moments(reviewCount: 6).map(\.fireDate) == [clock.date(15, 18)])   // Sunday 6 PM
        var settings = MomentSettings()
        settings.reviewWeekday = 4                                                   // Wednesday
        settings.reviewHour = 9
        #expect(moments(reviewCount: 6, settings: settings).map(\.fireDate) == [clock.date(11, 9)])
        #expect(moments(reviewCount: 0).isEmpty)
        settings.isReviewEnabled = false
        #expect(moments(reviewCount: 6, settings: settings).isEmpty)
    }

    @Test func withoutProOnlyTheWeeklyReviewComesBack() {
        let sale = item("Aeron chair", dates: [ItemDate(date: clock.date(20), hasTime: false, role: .expiry, source: .structured)], createdAt: clock.now)
        let due = ActionContext(action: ActionRecord(title: "Book a table", dueAt: clock.date(12, 15)))
        var settings = MomentSettings()
        settings.includesTimeMoments = false
        let found = moments(items: [sale], actions: [due], reviewCount: 3, settings: settings)
        #expect(found.map(\.reason) == [.weeklyReview])
    }

    @Test func settingsAreReadFromDefaults() throws {
        let suite = "MomentSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MomentSettings(defaults: defaults) == MomentSettings())
        defaults.set(false, forKey: MomentSettings.Key.enabled)
        defaults.set(5, forKey: MomentSettings.Key.maxPerDay)
        defaults.set(3, forKey: MomentSettings.Key.reviewWeekday)
        let settings = MomentSettings(defaults: defaults)
        #expect(!settings.isEnabled)
        #expect(settings.policy.maxPerDay == 5)
        #expect(settings.reviewWeekday == 3)
    }
}

struct MuteRuleTests {
    let clock = MomentClock()

    func entry(_ outcome: NotificationOutcome, daysAgo: Double, reason: String = "deadline") -> LedgerEntry {
        LedgerEntry(reason: reason, targetID: "x", outcome: outcome, recordedAt: clock.now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func threeDismissalsInARowMuteAType() {
        let entries = [entry(.dismissed, daysAgo: 1), entry(.dismissed, daysAgo: 2), entry(.dismissed, daysAgo: 3), entry(.opened, daysAgo: 4)]
        #expect(MuteRule.mutedReasons(entries, now: clock.now) == ["deadline"])
    }

    @Test func anyOtherAnswerBreaksTheStreak() {
        let entries = [entry(.dismissed, daysAgo: 1), entry(.opened, daysAgo: 2), entry(.dismissed, daysAgo: 3), entry(.dismissed, daysAgo: 4)]
        #expect(MuteRule.mutedReasons(entries, now: clock.now).isEmpty)
    }

    @Test func mutesLastThirtyDays() {
        let entries = [entry(.dismissed, daysAgo: 31), entry(.dismissed, daysAgo: 32), entry(.dismissed, daysAgo: 33)]
        #expect(MuteRule.mutedReasons(entries, now: clock.now).isEmpty)
    }
}

extension MomentGeneratorTests {
    // MARK: Shows and trips

    func show(startingAt start: Date) -> ItemRecord {
        var show = item("Swan Lake", createdAt: clock.now)
        show.typedFields = TypedFields(ticket: TicketFields(name: "Swan Lake", startDate: start, venue: "Royal Opera House"))
        show.dates = show.typedFields?.structuredDates ?? []
        return show
    }

    @Test func showsGetTheirRemindersFreeTheEveningBeforeAndTwoHoursBefore() {
        var settings = MomentSettings()
        settings.includesTimeMoments = false
        let concert = show(startingAt: clock.date(14, 19, 30))
        let reminders = moments(items: [concert], settings: settings).sorted { $0.fireDate < $1.fireDate }
        #expect(reminders.map(\.fireDate) == [clock.date(13, 18), clock.date(14, 17, 30)])
        #expect(reminders.allSatisfy { $0.isRequested && $0.reason == .eventStart })
        #expect(reminders.first?.body.hasSuffix("Royal Opera House") == true)
        #expect(Set(reminders.map(\.identifier)).count == 2)
    }

    @Test func eachLegOfAFlightIsRemindedOfAndAnItemCanChooseItsOwn() {
        var trip = item("Tokyo", createdAt: clock.now)
        trip.typedFields = TypedFields(trip: TripFields(mode: .flight, legs: [
            TripLeg(number: "MU 523", fromCode: "PVG", toCode: "NRT", departure: clock.date(15, 14, 5)),
            TripLeg(number: "MU 524", fromCode: "NRT", toCode: "PVG", departure: clock.date(20, 9)),
        ]))
        trip.dates = trip.typedFields?.structuredDates ?? []
        let defaults = moments(items: [trip]).map(\.fireDate).sorted()
        #expect(defaults == [clock.date(14, 14, 5), clock.date(15, 11, 5), clock.date(19, 9), clock.date(20, 6)])

        trip.reminders = [.before(minutes: 120)]
        let chosen = moments(items: [trip]).map(\.fireDate).sorted()
        #expect(chosen == [clock.date(15, 12, 5), clock.date(20, 7)])

        trip.reminders = []
        #expect(moments(items: [trip]).isEmpty)
    }

    @Test func setRemindersKeepTheirTimeInQuietHoursAndAboveTheDailyLimit() {
        let early = MomentCandidate(targetID: "a", fireDate: clock.date(11, 5), reason: .departure, slot: "before-180.0")
        let others = (0..<5).map { MomentCandidate(targetID: "b\($0)", fireDate: clock.date(11, 12), reason: .deadline) }
        let plan = MomentPlanner(policy: MomentPolicy(maxPerDay: 3), calendar: clock.calendar).plan([early] + others, now: clock.now)
        #expect(plan.contains { $0.targetID == "a" && $0.fireDate == clock.date(11, 5) })
        #expect(plan.filter { $0.reason == .deadline }.count == 3)
    }
}
