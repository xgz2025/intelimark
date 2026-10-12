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

actor FakeScheduler: MomentScheduling {
    private(set) var plans: [[MomentCandidate]] = []
    private(set) var snoozed: [MomentCandidate] = []
    var delivered: [Date] = []

    func replaceMoments(with plan: [MomentCandidate]) async { plans.append(plan) }
    func snooze(_ moment: MomentCandidate) async { snoozed.append(moment) }

    func pruneSnoozes(keeping relevant: [MomentCandidate]) async {
        let kept = Set(relevant.map(\.identifier))
        snoozed.removeAll { !kept.contains($0.identifier) }
    }

    func committedFireDates() async -> [Date] { delivered + snoozed.map(\.fireDate) }

    func deliver(_ dates: [Date]) { delivered += dates }
}

struct MomentsEngineTests {
    let clock = MomentClock()
    let database: LibraryDatabase
    let scheduler = FakeScheduler()
    var engine: MomentsEngine { MomentsEngine(database: database, scheduler: scheduler, calendar: clock.calendar) }

    init() throws {
        database = try LibraryDatabase.inMemory()
    }

    func insert(_ record: ItemRecord) async throws {
        try await database.writer.write { db in try record.insert(db) }
    }

    @Test func schedulesWhatTheLibraryKnows() async throws {
        let sale = item("Aeron chair", dates: [ItemDate(date: clock.date(20), hasTime: false, role: .expiry, source: .structured)], createdAt: clock.now)
        try await insert(sale)
        try await ActionRepository(database: database).add(title: "Measure the desk", dueAt: clock.date(12), now: clock.now)

        let plan = try await engine.reschedule(settings: MomentSettings(), now: clock.now)
        #expect(Set(plan.map(\.reason)) == [.expiry, .actionDue, .weeklyReview])
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
        #expect(await scheduler.plans.last == plan)
    }

    @Test func dateRemindersOffLeavesTheWeeklyReview() async throws {
        try await insert(item("Sale", dates: [ItemDate(date: clock.date(20), hasTime: false, role: .expiry, source: .structured)], createdAt: clock.now))
        var settings = MomentSettings()
        settings.isEnabled = false
        #expect(try await engine.reschedule(settings: settings, now: clock.now).map(\.reason) == [.weeklyReview])
        settings.isReviewEnabled = false
        #expect(try await engine.reschedule(settings: settings, now: clock.now).isEmpty)
        #expect(await scheduler.plans.last == [])
    }

    @Test func dismissedTypesAreMuted() async throws {
        try await insert(item("Sale", dates: [ItemDate(date: clock.date(20), hasTime: false, role: .expiry, source: .structured)], createdAt: clock.now))
        for daysAgo in 1...3 {
            let response = MomentResponse(action: .dismiss, reason: .expiry, targetID: "old\(daysAgo)", targetKind: .item)
            try await engine.handle(response, now: clock.now.addingTimeInterval(-Double(daysAgo) * 86_400))
        }
        let plan = try await engine.reschedule(settings: MomentSettings(), now: clock.now)
        #expect(!plan.contains { $0.reason == .expiry })
    }

    @Test func doneAndSnoozeAreCarriedOut() async throws {
        let actions = ActionRepository(database: database)
        let id = try await actions.add(title: "Book a table", dueAt: clock.date(12), now: clock.now)

        let done = MomentResponse(action: .done, reason: .actionDue, targetID: id, targetKind: .action)
        #expect(try await engine.handle(done, now: clock.now) == nil)
        #expect(try await actions.openActions().isEmpty)

        let snooze = MomentResponse(action: .snooze, reason: .eventStart, targetID: "item", targetKind: .item, title: "Concert", body: "Soon")
        try await engine.handle(snooze, now: clock.now)
        let snoozed = try #require(await scheduler.snoozed.first)
        #expect(snoozed.fireDate == clock.date(11, 9))
        #expect(snoozed.title == "Concert")

        let entries = try await NotificationLedger(database: database).entries(since: clock.date(1))
        #expect(Set(entries.map(\.outcome)) == [.done, .snoozed])
    }

    @Test func snoozesEndWithTheirSubject() async throws {
        let concert = item(
            "Concert", dates: [ItemDate(date: clock.date(11, 19), hasTime: true, role: .eventStart, source: .structured)],
            status: .active, createdAt: clock.now
        )
        try await insert(concert)
        let plan = try await engine.reschedule(settings: MomentSettings(), now: clock.now)
        let moment = try #require(plan.first { $0.targetID == concert.id })
        #expect(moment.latest == clock.date(11, 19))

        // Remind me tomorrow at 9, the day of the concert: kept while the concert is ahead.
        let response = try #require(MomentResponse(
            actionIdentifier: "moment.snooze", userInfo: MomentResponse.userInfo(for: moment), title: "Concert", body: ""
        ))
        try await engine.handle(response, now: clock.now)
        try await engine.reschedule(settings: MomentSettings(), now: clock.now)
        #expect(await scheduler.snoozed.count == 1)

        // Trashed: the snooze goes too.
        try await ItemRepository(database: database).setStatus(.trashed, forItem: concert.id, now: clock.now)
        try await engine.reschedule(settings: MomentSettings(), now: clock.now)
        #expect(await scheduler.snoozed.isEmpty)
    }

    @Test func noSnoozePastTheEvent() async throws {
        // Tonight's concert can't wait until tomorrow morning.
        let response = MomentResponse(
            action: .snooze, reason: .eventStart, targetID: "item", targetKind: .item, latest: clock.date(10, 20)
        )
        try await engine.handle(response, now: clock.now)
        #expect(await scheduler.snoozed.isEmpty)
    }

    @Test func deliveredMomentsUseUpTheDay() async throws {
        let actions = ActionRepository(database: database)
        for index in 0..<3 {
            try await actions.add(title: "Errand \(index)", dueAt: clock.date(12), now: clock.now)
        }
        var settings = MomentSettings()
        settings.isReviewEnabled = false
        #expect(try await engine.reschedule(settings: settings, now: clock.now).count == 3)

        await scheduler.deliver([clock.date(12, 8), clock.date(12, 8, 30)])
        #expect(try await engine.reschedule(settings: settings, now: clock.date(12, 8, 45)).count == 1)
    }

    @Test func openingLeadsToTheTarget() async throws {
        let open = { (kind: MomentCandidate.TargetKind) in MomentResponse(action: .open, reason: .planDate, targetID: "g", targetKind: kind) }
        #expect(try await engine.handle(open(.group), now: clock.now) == .group("g"))
        #expect(try await engine.handle(open(.item), now: clock.now) == .item("g"))
        #expect(try await engine.handle(open(.action), now: clock.now) == .nextActions)
        #expect(try await engine.handle(open(.review), now: clock.now) == .weeklyReview)
    }

    @Test func responsesAreReadFromNotifications() {
        let moment = MomentCandidate(targetID: "abc", targetKind: .item, fireDate: clock.now, reason: .deadline, title: "T", body: "B")
        let userInfo: [AnyHashable: Any] = MomentResponse.userInfo(for: moment)
        let tapped = MomentResponse(
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: userInfo, title: "T", body: "B"
        )
        #expect(tapped == MomentResponse(action: .open, reason: .deadline, targetID: "abc", targetKind: .item, title: "T", body: "B"))
        let swiped = MomentResponse(actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier", userInfo: userInfo, title: "", body: "")
        #expect(swiped?.action == .dismiss)
        #expect(MomentResponse(actionIdentifier: "moment.done", userInfo: userInfo, title: "", body: "")?.action == .done)
        #expect(MomentResponse(actionIdentifier: "x", userInfo: [:], title: "", body: "") == nil)
    }
}

struct ReviewQueueTests {
    let clock = MomentClock()

    @Test func upcomingAndActionableFirstThenNewThenStale() {
        let now = clock.now
        let upcoming = item("Concert", dates: [ItemDate(date: clock.date(15), hasTime: false, role: .eventStart, source: .structured)],
                            status: .active, createdAt: clock.date(1, month: 9))
        let actionable = item("Desk", status: .active, createdAt: clock.date(1, month: 10))
        let new = item("Ramen", createdAt: clock.date(8))
        let stale = item("Old article", status: .active, createdAt: clock.date(1, month: 8))
        let fresh = item("Recent, opened", status: .active, createdAt: clock.date(9))
        let cards = ItemRepository.reviewCards(
            items: [new, fresh, actionable, upcoming, stale], openActions: [actionable.id: 2], now: now, limit: 15
        )
        #expect(cards.map(\.item.id) == [actionable.id, upcoming.id, new.id, stale.id])
        #expect(cards.map(\.reason) == [.hasActions(2), .comingUp(clock.date(15)), .new, .stale])
    }
}
