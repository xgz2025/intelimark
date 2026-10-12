//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

#if canImport(UserNotifications)
import Foundation
import UserNotifications

/// Schedules Moments as local notifications (Docs/architecture.md §8). Permission
/// is asked the first time there is something to schedule, never at launch.
public struct UserNotificationScheduler: MomentScheduling {
    static let momentPrefix = "moment."
    static let snoozePrefix = "snooze."

    public init() {}

    /// Notification actions: Done, Tomorrow, Not Interested (PRD M5 learns from the last).
    public static func registerCategories() {
        let done = UNNotificationAction(identifier: MomentResponse.Action.done.rawValue, title: String(localized: "Mark as Done"), options: [])
        let snooze = UNNotificationAction(identifier: MomentResponse.Action.snooze.rawValue, title: String(localized: "Remind Me Tomorrow"), options: [])
        let dismiss = UNNotificationAction(
            identifier: MomentResponse.Action.dismiss.rawValue, title: String(localized: "Not Interested"), options: [.destructive]
        )
        func category(_ kind: MomentCandidate.TargetKind, _ actions: [UNNotificationAction]) -> UNNotificationCategory {
            UNNotificationCategory(identifier: categoryID(kind), actions: actions, intentIdentifiers: [], options: [.customDismissAction])
        }
        UNUserNotificationCenter.current().setNotificationCategories([
            category(.item, [done, snooze, dismiss]),
            category(.action, [done, snooze]),
            category(.group, [snooze, dismiss]),
            category(.review, [snooze]),
        ])
    }

    public func replaceMoments(with plan: [MomentCandidate]) async {
        let center = UNUserNotificationCenter.current()
        if !plan.isEmpty, await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let scheduled = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.momentPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled)
        for moment in plan {
            try? await center.add(Self.request(for: moment, identifier: moment.identifier))
        }
    }

    public func snooze(_ moment: MomentCandidate) async {
        try? await UNUserNotificationCenter.current().add(Self.request(for: moment, identifier: Self.snoozePrefix + moment.identifier))
    }

    static func categoryID(_ kind: MomentCandidate.TargetKind) -> String {
        "moment.\(kind.rawValue)"
    }

    static func request(for moment: MomentCandidate, identifier: String, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = moment.title
        content.body = moment.body
        content.sound = .default
        content.categoryIdentifier = categoryID(moment.targetKind)
        content.threadIdentifier = moment.reason.rawValue
        content.userInfo = MomentResponse.userInfo(for: moment)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
#endif
