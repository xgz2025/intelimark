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
import SwiftUI

/// The menu-bar extra (PRD C5): quick capture, one-click clipboard save, and a
/// way back into the app.
struct QuickCaptureMenu: View {
    @AppStorage(QuickCaptureController.hotKeyEnabledKey) private var hotKeyEnabled = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        quickCaptureButton
        Button("Save Clipboard") { QuickCaptureController.shared.saveClipboard() }
        Button("Capture Screenshot…") { QuickCaptureController.shared.show(source: .screenshot) }
        Divider()
        Button("Open Laterwise") {
            openWindow(id: NextmarkApp.mainWindowID)
            NSApp.activate()
        }
        // Brought forward: from the menu bar, Settings would open behind other apps.
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Laterwise") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Shows ⌥⌘S next to the item while the global hotkey is on.
    @ViewBuilder
    private var quickCaptureButton: some View {
        let button = Button("Quick Capture…") { QuickCaptureController.shared.show() }
        if hotKeyEnabled {
            button.keyboardShortcut("s", modifiers: [.command, .option])
        } else {
            button
        }
    }
}
