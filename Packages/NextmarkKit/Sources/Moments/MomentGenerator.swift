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

/// The user's Moments settings (PRD M2, M5), kept in UserDefaults so the
/// Settings screen can bind to the same keys.
public struct MomentSettings: Sendable, Equatable {
    public enum Key {
        public static let enabled = "moments.enabled"
        public static let maxPerDay = "moments.maxPerDay"
        public static let quietStart = "moments.quietStart"
        public static let quietEnd = "moments.quietEnd"
        public static let reviewEnabled = "moments.reviewEnabled"
        public static let reviewWeekday = "moments.reviewWeekday"
        public static let reviewHour = "moments.reviewHour"
    }

    public var isEnabled = true
    public var policy = MomentPolicy()
    public var isReviewEnabled = true
    /// `Calendar` weekday: 1 is Sunday.
    public var reviewWeekday = 1
    public var reviewHour = 18

    public init() {}

    public init(defaults: UserDefaults) {
        func value<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: key) as? T ?? fallback }
        isEnabled = value(Key.enabled, true)
        policy.maxPerDay = value(Key.maxPerDay, policy.maxPerDay)
        policy.quietHoursStart = value(Key.quietStart, policy.quietHoursStart)
        policy.quietHoursEnd = value(Key.quietEnd, policy.quietHoursEnd)
        isReviewEnabled = value(Key.reviewEnabled, true)
        reviewWeekday = value(Key.reviewWeekday, reviewWeekday)
        reviewHour = value(Key.reviewHour, reviewHour)
    }
}

/// Turns dates the library knows about into Moment candidates (PRD M1, M2).
/// Pure: same records, settings and clock give the same candidates. Wording is
/// absolute ("Ends Saturday, Oct 31"), so it stays true whenever it's delivered.
public struct MomentGenerator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// How far ahead dates are considered.
    static let horizon: TimeInterval = 365 * 86_400

    public func candidates(
        items: [ItemRecord],
        plans: [GroupSummary],
        actions: [ActionContext],
        reviewCount: Int,
        settings: MomentSettings,
        now: Date
    ) -> [MomentCandidate] {
        var candidates: [MomentCandidate] = []
        for item in items where item.status == .inbox || item.status == .active {
            candidates += itemMoments(item, now: now)
        }
        for plan in plans {
            if let moment = planMoment(plan, now: now) { candidates.append(moment) }
        }
        for context in actions {
            if let moment = actionMoment(context, now: now) { candidates.append(moment) }
        }
        if settings.isReviewEnabled, reviewCount > 0, let moment = reviewMoment(count: reviewCount, settings: settings, now: now) {
            candidates.append(moment)
        }
        return candidates.filter { $0.fireDate > now }
    }

    // MARK: Rules

    /// One Moment per item: its earliest upcoming date that is worth a notification.
    func itemMoments(_ item: ItemRecord, now: Date) -> [MomentCandidate] {
        let title = String(item.displayTitle.prefix(80))
        let upcoming = item.dates
            .filter { $0.date > now && $0.date < now.addingTimeInterval(Self.horizon) && $0.role != .mentioned && $0.role != .eventEnd }
            .sorted { $0.date < $1.date }
        guard let date = upcoming.first else { return [] }
        let when = describe(date)
        let fire: Date?
        let body: String
        let reason: MomentCandidate.Reason
        let priority: Int
        switch date.role {
        case .eventStart:
            // The evening before; for a timed event also fine on the day itself.
            let evening = dayBefore(date.date, hour: 18)
            fire = date.hasTime ? firstAhead(evening, otherwise: date.date.addingTimeInterval(-3 * 3600), now: now) : evening
            body = String(localized: "Coming up \(when)")
            reason = .eventStart
            priority = 2
        case .deadline:
            fire = dayBefore(date.date, hour: 10)
            body = String(localized: "Deadline \(when)")
            reason = .deadline
            priority = 3
        case .expiry:
            fire = dayBefore(date.date, hour: 10)
            body = String(localized: "Ends \(when)")
            reason = .expiry
            priority = 3
        case .reservation:
            fire = date.hasTime ? date.date.addingTimeInterval(-3 * 3600) : at(date.date, hour: 9)
            body = String(localized: "Reservation \(when)")
            reason = .reservation
            priority = 3
        case .mentioned, .eventEnd:
            return []
        }
        guard let fire else { return [] }
        return [MomentCandidate(targetID: item.id, targetKind: .item, fireDate: fire, reason: reason, priority: priority, title: title, body: body)]
    }

    /// Plans come back five days before their date, then the day before (PRD G6, M1).
    func planMoment(_ plan: GroupSummary, now: Date) -> MomentCandidate? {
        guard let target = plan.group.targetDate, target > now else { return nil }
        let fire = [
            calendar.date(byAdding: .day, value: -5, to: at(target, hour: 9) ?? target),
            dayBefore(target, hour: 9),
        ]
        .compactMap { $0 }
        .first { $0 > now }
        guard let fire else { return nil }
        let title = [plan.group.emoji, plan.group.displayTitle].compactMap { $0 }.joined(separator: " ")
        let date = target.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let body = plan.openActionCount > 0
            ? String(localized: "\(date) · \(plan.memberCount) saves, \(plan.openActionCount) open actions")
            : String(localized: "\(date) · \(plan.memberCount) saves")
        return MomentCandidate(targetID: plan.id, targetKind: .group, fireDate: fire, reason: .planDate, priority: 2, title: title, body: body)
    }

    /// Actions are due in the morning of their day.
    func actionMoment(_ context: ActionContext, now: Date) -> MomentCandidate? {
        guard let due = context.action.dueAt, let fire = at(due, hour: 9), fire > now else { return nil }
        let body: String
        if let group = context.groupTitle {
            body = [context.groupEmoji, group].compactMap { $0 }.joined(separator: " ")
        } else {
            body = context.itemTitle ?? ""
        }
        return MomentCandidate(
            targetID: context.action.id, targetKind: .action, fireDate: fire, reason: .actionDue, priority: 3,
            title: String(localized: "Due today: \(context.action.title)"), body: body
        )
    }

    func reviewMoment(count: Int, settings: MomentSettings, now: Date) -> MomentCandidate? {
        let components = DateComponents(hour: settings.reviewHour, minute: 0, weekday: settings.reviewWeekday)
        guard let fire = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { return nil }
        return MomentCandidate(
            targetID: "weekly", targetKind: .review, fireDate: fire, reason: .weeklyReview, priority: 1,
            title: String(localized: "Your weekly review is ready"),
            body: String(localized: "\(count) saves to sort: do, keep or toss.")
        )
    }

    // MARK: Dates

    func at(_ date: Date, hour: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
    }

    func dayBefore(_ date: Date, hour: Int) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))
            .flatMap { at($0, hour: hour) }
    }

    /// `preferred` while it is still ahead, else `fallback`.
    func firstAhead(_ preferred: Date?, otherwise fallback: Date, now: Date) -> Date? {
        guard let preferred, preferred > now else { return fallback }
        return preferred
    }

    func describe(_ date: ItemDate) -> String {
        date.hasTime
            ? date.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
            : date.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// Mutes a Moment type after it was dismissed three times in a row, for 30 days (PRD M5).
public enum MuteRule {
    public static let dismissalsInARow = 3
    public static let duration: TimeInterval = 30 * 86_400

    /// `entries` newest first.
    public static func mutedReasons(_ entries: [LedgerEntry], now: Date) -> Set<String> {
        var muted = Set<String>()
        for (reason, history) in Dictionary(grouping: entries, by: \.reason) {
            let recent = history.prefix(dismissalsInARow)
            guard recent.count == dismissalsInARow,
                  recent.allSatisfy({ $0.outcome == .dismissed }),
                  let latest = recent.first, now.timeIntervalSince(latest.recordedAt) < duration
            else { continue }
            muted.insert(reason)
        }
        return muted
    }
}
