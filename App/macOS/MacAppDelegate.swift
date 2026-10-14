//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Right-click → Services → Save to Laterwise (PRD C4).
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
        // ⌥⌘S quick capture from any app (PRD C5).
        QuickCaptureController.shared.updateHotKey()
    }

    /// Closing the last window leaves the menu-bar item and the hotkey working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
