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
    @State private var model: AppModel
    @State private var startupErrorSeen = false
    @Environment(\.scenePhase) private var scenePhase

    static let mainWindowID = "main"

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        // From launch, not from a window: on the Mac, captures from the menu bar, hotkey
        // and Services arrive with no window open.
        Task { await model.start() }
    }

    var body: some Scene {
        #if os(macOS)
        // One main window: "Open Nextmark" brings it back instead of adding another.
        Window("Nextmark", id: Self.mainWindowID) { main }
        #else
        WindowGroup(id: Self.mainWindowID) { main }
        #endif
        #if os(macOS)
        MenuBarExtra("Nextmark", systemImage: "bookmark.fill") {
            QuickCaptureMenu()
        }
        Settings {
            MacSettingsView(onChange: model.services.refresh, onSyncNow: model.services.syncNow)
                .environment(model.pro)
        }
        #endif
    }

    private var main: some View {
        RootView(services: model.services, navigator: model.navigator, rescue: model.rescue)
            .environment(model.pro)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.becameActive() }
                }
            }
            .alert(
                "Nextmark Couldn't Open Your Library",
                isPresented: Binding(get: { model.startupError != nil && !startupErrorSeen }, set: { _ in startupErrorSeen = true })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing has been lost: new saves wait in the Inbox until the library opens. Quit and reopen Nextmark, and if this keeps happening, contact support. (\(model.startupError ?? ""))")
            }
    }
}
