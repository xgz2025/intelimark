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
import Features

@main
struct NextmarkApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    static let mainWindowID = "main"

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            RootView(services: model.services, navigator: model.navigator, rescue: model.rescue)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.becameActive() }
                    }
                }
        }
        #if os(macOS)
        MenuBarExtra("Nextmark", systemImage: "bookmark.fill") {
            QuickCaptureMenu()
        }
        Settings {
            MacSettingsView(onChange: model.services.refresh, onSyncNow: model.services.syncNow)
        }
        #endif
    }
}
