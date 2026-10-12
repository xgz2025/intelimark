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

    public init(
        action: Action, reason: MomentCandidate.Reason, targetID: String,
        targetKind: MomentCandidate.TargetKind, title: String = "", body: String = ""
    ) {
        self.action = action
        self.reason = reason
        self.targetID = targetID
        self.targetKind = targetKind
        self.title = title
        self.body = body
    }

    /// Reads a response's action identifier and the `userInfo` a Moment was scheduled with.
    public init?(actionIdentifier: String, userInfo: [AnyHashable: Any], title: String, body: String) {
        guard let reason = (userInfo["reason"] as? String).flatMap(MomentCandidate.Reason.init(rawValue:)),
              let targetID = userInfo["targetID"] as? String,
              let kind = (userInfo["targetKind"] as? String).flatMap(MomentCandidate.TargetKind.init(rawValue:))
        else { return nil }
        self.init(
            action: Action(rawValue: actionIdentifier) ?? (actionIdentifier.hasSuffix("DismissActionIdentifier") ? .dismiss : .open),
            reason: reason, targetID: targetID, targetKind: kind, title: title, body: body
        )
    }

    /// The `userInfo` a Moment is scheduled with.
    public static func userInfo(for moment: MomentCandidate) -> [String: String] {
        ["reason": moment.reason.rawValue, "targetID": moment.targetID, "targetKind": moment.targetKind.rawValue]
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
        guard settings.isEnabled else {
            await scheduler.replaceMoments(with: [])
            return []
        }
        let candidates = generator.candidates(
            items: try await items.itemsWithDates(),
            plans: try await groups.plans(),
            actions: try await actions.openActions(),
            reviewCount: try await items.reviewQueue(now: now).count,
            settings: settings,
            now: now
        )
        let muted = MuteRule.mutedReasons(try await ledger.entries(since: now.addingTimeInterval(-MuteRule.duration)), now: now)
        let plan = MomentPlanner(policy: settings.policy, calendar: generator.calendar)
            .plan(candidates.filter { !muted.contains($0.reason.rawValue) }, now: now)
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
            if let tomorrow {
                await scheduler.snooze(MomentCandidate(
                    targetID: response.targetID, targetKind: response.targetKind, fireDate: tomorrow,
                    reason: response.reason, title: response.title, body: response.body
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
