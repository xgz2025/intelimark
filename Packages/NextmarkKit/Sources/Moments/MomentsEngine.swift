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
import Library

/// Delivers Moments. The app uses `UserNotificationScheduler`; tests use a fake.
public protocol MomentScheduling: Sendable {
    /// Replaces every scheduled Moment with `plan` (snoozed ones stay).
    func replaceMoments(with plan: [MomentCandidate]) async
    /// Schedules one Moment again, outside the plan.
    func snooze(_ moment: MomentCandidate) async
    /// Cancels snoozed Moments whose subject no longer matters: it was done, trashed
    /// or deleted, or its date passed.
    func pruneSnoozes(keeping relevant: [MomentCandidate]) async
    /// When Moments already delivered, and snoozed ones still waiting, fire.
    func committedFireDates() async -> [Date]
}

/// Where tapping a Moment leads.
public enum MomentDestination: Sendable, Equatable {
    case item(String)
    case group(String)
    case nextActions
    case weeklyReview
}

/// A notification answer, already taken apart (UserNotifications types stay in the app).
public struct MomentResponse: Sendable, Equatable {
    public enum Action: String, Sendable {
        case open
        case done = "moment.done"
        case snooze = "moment.snooze"
        case dismiss = "moment.dismiss"
    }

    public var action: Action
    public var reason: MomentCandidate.Reason
    public var targetID: String
    public var targetKind: MomentCandidate.TargetKind
    public var title: String
    public var body: String
    /// The Moment's `latest`: a snooze never goes past it.
    public var latest: Date?

    public init(
        action: Action, reason: MomentCandidate.Reason, targetID: String,
        targetKind: MomentCandidate.TargetKind, title: String = "", body: String = "", latest: Date? = nil
    ) {
        self.action = action
        self.reason = reason
        self.targetID = targetID
        self.targetKind = targetKind
        self.title = title
        self.body = body
        self.latest = latest
    }

    /// Reads a response's action identifier and the `userInfo` a Moment was scheduled with.
    public init?(actionIdentifier: String, userInfo: [AnyHashable: Any], title: String, body: String) {
        guard let reason = (userInfo["reason"] as? String).flatMap(MomentCandidate.Reason.init(rawValue:)),
              let targetID = userInfo["targetID"] as? String,
              let kind = (userInfo["targetKind"] as? String).flatMap(MomentCandidate.TargetKind.init(rawValue:))
        else { return nil }
        self.init(
            action: Action(rawValue: actionIdentifier) ?? (actionIdentifier.hasSuffix("DismissActionIdentifier") ? .dismiss : .open),
            reason: reason, targetID: targetID, targetKind: kind, title: title, body: body,
            latest: (userInfo["latest"] as? String).flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// The `userInfo` a Moment is scheduled with.
    public static func userInfo(for moment: MomentCandidate) -> [String: String] {
        var userInfo = ["reason": moment.reason.rawValue, "targetID": moment.targetID, "targetKind": moment.targetKind.rawValue]
        if let latest = moment.latest {
            userInfo["latest"] = String(latest.timeIntervalSince1970)
        }
        return userInfo
    }
}

/// Plans Moments from the library and answers their notifications (Docs/architecture.md §8).
public struct MomentsEngine: Sendable {
    let items: ItemRepository
    let groups: GroupRepository
    let actions: ActionRepository
    let ledger: NotificationLedger
    let scheduler: any MomentScheduling
    public var generator: MomentGenerator

    public init(database: LibraryDatabase, scheduler: any MomentScheduling, calendar: Calendar = .current) {
        items = ItemRepository(database: database)
        groups = GroupRepository(database: database)
        actions = ActionRepository(database: database)
        ledger = NotificationLedger(database: database)
        self.scheduler = scheduler
        generator = MomentGenerator(calendar: calendar)
    }

    /// Recomputes the plan and hands it to the scheduler. Call after enrichment,
    /// at launch, and when settings change. Returns what was scheduled.
    @discardableResult
    public func reschedule(settings: MomentSettings, now: Date = Date()) async throws -> [MomentCandidate] {
        // Date reminders off still leaves the Weekly Review, which has its own switch.
        let relevant = generator.relevant(
            items: try await items.itemsWithDates(),
            plans: try await groups.plans(),
            actions: try await actions.openActions(),
            reviewCount: try await items.reviewQueue(now: now).count,
            settings: settings,
            now: now
        )
        // A snooze was asked for, so a muted type doesn't cancel it; only its subject passing does.
        await scheduler.pruneSnoozes(keeping: relevant)
        let muted = MuteRule.mutedReasons(try await ledger.entries(since: now.addingTimeInterval(-MuteRule.duration)), now: now)
        let candidates = generator.candidates(from: relevant, now: now).filter { !muted.contains($0.reason.rawValue) }
        let plan = MomentPlanner(policy: settings.policy, calendar: generator.calendar)
            .plan(candidates, now: now, committed: await scheduler.committedFireDates())
        await scheduler.replaceMoments(with: plan)
        return plan
    }

    /// Records the answer, carries out Done and Snooze, and says where to go for Open.
    @discardableResult
    public func handle(_ response: MomentResponse, now: Date = Date()) async throws -> MomentDestination? {
        let outcome: NotificationOutcome
        var destination: MomentDestination?
        switch response.action {
        case .open:
            outcome = .opened
            destination = Self.destination(for: response)
        case .done:
            outcome = .done
            switch response.targetKind {
            case .action: try await actions.setDone(true, forAction: response.targetID, now: now)
            case .item: try await items.setStatus(.done, forItem: response.targetID, now: now)
            case .group: try await groups.setStatus(.done, forGroup: response.targetID, now: now)
            case .review: break
            }
        case .snooze:
            outcome = .snoozed
            let tomorrow = generator.calendar.date(byAdding: .day, value: 1, to: now).flatMap { generator.at($0, hour: 9) }
            // Tomorrow is too late for something that's over by then.
            if let tomorrow, response.latest.map({ tomorrow < $0 }) ?? true {
                await scheduler.snooze(MomentCandidate(
                    targetID: response.targetID, targetKind: response.targetKind, fireDate: tomorrow,
                    reason: response.reason, title: response.title, body: response.body, latest: response.latest
                ))
            }
        case .dismiss:
            outcome = .dismissed
        }
        try await ledger.record(reason: response.reason.rawValue, targetID: response.targetID, outcome: outcome, now: now)
        return destination
    }

    static func destination(for response: MomentResponse) -> MomentDestination {
        switch response.targetKind {
        case .item: .item(response.targetID)
        case .group: .group(response.targetID)
        case .action: .nextActions
        case .review: .weeklyReview
        }
    }
}
