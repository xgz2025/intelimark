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

/// Something that could resurface an item, group or action at a given time (PRD M1, M2).
public struct MomentCandidate: Sendable, Hashable {
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        case eventStart, deadline, expiry, reservation, planDate, actionDue, weeklyReview, recap
    }

    public enum TargetKind: String, Sendable, Hashable {
        case item, group, action, review
    }

    public var targetID: String
    public var targetKind: TargetKind
    public var fireDate: Date
    public var reason: Reason
    /// Higher wins when a day is over budget.
    public var priority: Int
    public var title: String
    public var body: String

    public init(
        targetID: String,
        targetKind: TargetKind = .item,
        fireDate: Date,
        reason: Reason,
        priority: Int = 0,
        title: String = "",
        body: String = ""
    ) {
        self.targetID = targetID
        self.targetKind = targetKind
        self.fireDate = fireDate
        self.reason = reason
        self.priority = priority
        self.title = title
        self.body = body
    }

    /// Stable per target and reason, so rescheduling replaces rather than duplicates.
    public var identifier: String { "moment.\(reason.rawValue).\(targetID)" }
}

public struct MomentPolicy: Sendable, Equatable {
    public var maxPerDay: Int
    /// Hours in the user's calendar; quiet hours may wrap past midnight.
    public var quietHoursStart: Int
    public var quietHoursEnd: Int
    /// iOS keeps at most 64 pending local notifications per app; leave headroom.
    public var maxPending: Int

    public init(maxPerDay: Int = 3, quietHoursStart: Int = 22, quietHoursEnd: Int = 8, maxPending: Int = 40) {
        self.maxPerDay = maxPerDay
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.maxPending = maxPending
    }
}

/// Decides which Moments to schedule (Docs/architecture.md §8). Pure and
/// deterministic: same candidates, clock and calendar give the same plan.
public struct MomentPlanner: Sendable {
    public var policy: MomentPolicy
    public var calendar: Calendar

    public init(policy: MomentPolicy = MomentPolicy(), calendar: Calendar = .current) {
        self.policy = policy
        self.calendar = calendar
    }

    public func plan(_ candidates: [MomentCandidate], now: Date) -> [MomentCandidate] {
        let upcoming = candidates
            .filter { $0.fireDate > now }
            .map { candidate -> MomentCandidate in
                var moved = candidate
                moved.fireDate = outsideQuietHours(candidate.fireDate)
                return moved
            }
        let byDay = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.fireDate) }
        let withinBudget = byDay.values.flatMap { day in
            day.sorted { lhs, rhs in
                lhs.priority != rhs.priority ? lhs.priority > rhs.priority : lhs.fireDate < rhs.fireDate
            }
            .prefix(policy.maxPerDay)
        }
        return Array(
            withinBudget
                .sorted { $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.targetID < $1.targetID }
                .prefix(policy.maxPending)
        )
    }

    /// Moves a date that falls in quiet hours to the end of them.
    func outsideQuietHours(_ date: Date) -> Date {
        let start = policy.quietHoursStart
        let end = policy.quietHoursEnd
        guard start != end else { return date }
        let hour = calendar.component(.hour, from: date)
        let wraps = start > end
        let isQuiet = wraps ? (hour >= start || hour < end) : (hour >= start && hour < end)
        guard isQuiet else { return date }
        var day = calendar.startOfDay(for: date)
        if wraps && hour >= start, let next = calendar.date(byAdding: .day, value: 1, to: day) {
            day = next
        }
        return calendar.date(bySettingHour: end, minute: 0, second: 0, of: day) ?? date
    }
}
