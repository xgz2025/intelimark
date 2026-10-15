//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Permission to notify, asked for when it's clear why: on the onboarding page that
/// explains Moments, or when a reminder is turned on in Settings.
enum NotificationAccess {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once; later calls return what was answered.
    @discardableResult
    static func request() async -> Bool {
        guard await status() == .notDetermined else { return await status() == .authorized }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// This app's page in Notifications settings.
    @MainActor
    static var settingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #endif
    }
}

/// Says when notifications are off, with the way to turn them on.
struct NotificationAccessRow: View {
    /// Whether any reminder is on; there's nothing to say otherwise.
    let isNeeded: Bool
    @State private var status: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isNeeded {
                switch status {
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notifications are off for Laterwise, so reminders can't reach you.", systemImage: "bell.slash")
                            .foregroundStyle(.secondary)
                        if let url = NotificationAccess.settingsURL {
                            Button("Turn On in Settings…") { openURL(url) }
                        }
                    }
                case .notDetermined:
                    Button("Allow Notifications", systemImage: "bell.badge") {
                        Task {
                            await NotificationAccess.request()
                            status = await NotificationAccess.status()
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
        // Back from System Settings: show the new answer.
        .task(id: scenePhase) { status = await NotificationAccess.status() }
        .onChange(of: isNeeded) { _, needed in
            guard needed else { return }
            Task {
                await NotificationAccess.request()
                status = await NotificationAccess.status()
            }
        }
    }
}
