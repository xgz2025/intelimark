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
import Features

/// The Mac Settings window: the shared settings plus capture options.
struct MacSettingsView: View {
    var onChange: @Sendable () async -> Void = {}
    var onSyncNow: @Sendable () async -> Void = {}

    var body: some View {
        TabView {
            SettingsView(onChange: onChange, onSyncNow: onSyncNow)
                .tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "square.and.arrow.down") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct CaptureSettingsView: View {
    @AppStorage(QuickCaptureController.hotKeyEnabledKey) private var hotKeyEnabled = true
    @State private var hotKeyTaken = false

    var body: some View {
        Form {
            Section("Quick Capture") {
                Toggle(isOn: $hotKeyEnabled) {
                    Text("Open with \(GlobalHotKey.Combo.quickCapture.symbol) from any app")
                    Text("Save the clipboard or a screenshot, or drop a link, file or image on the panel.")
                }
                if hotKeyTaken {
                    Label("Another app is already using this shortcut.", systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
            Section("Services") {
                Text("Select text or a link in any app, or files in Finder, then Control-click and choose Services › Save to Nextmark.")
                    .foregroundStyle(.secondary)
            }
            Section("Screenshots") {
                Text("Nextmark asks for Screen Recording permission the first time you capture a screenshot. Its own windows are never included.")
                    .foregroundStyle(.secondary)
                if let url = ScreenshotCapture.privacySettingsURL {
                    Button("Open Privacy Settings…") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: hotKeyEnabled, initial: true) {
            QuickCaptureController.shared.updateHotKey()
            hotKeyTaken = hotKeyEnabled && !QuickCaptureController.shared.isHotKeyRegistered
        }
    }
}
