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
import UserNotifications
import Moments

/// Receives notification answers (Open, Done, Remind Me Tomorrow, Not Interested,
/// swiped away) and passes them on as `MomentResponse`s. Shows Moments as banners
/// while the app is in front, too.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let handle: @Sendable (MomentResponse) async -> Void

    init(handle: @escaping @Sendable (MomentResponse) async -> Void) {
        self.handle = handle
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard let moment = MomentResponse(
            actionIdentifier: response.actionIdentifier,
            userInfo: content.userInfo,
            title: content.title,
            body: content.body
        ) else { return }
        await handle(moment)
    }
}
