import SwiftUI
import Features

@main
struct NextmarkApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(repository: model.repository)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.processInbox() }
                    }
                }
        }
        #if os(macOS)
        MenuBarExtra("Nextmark", systemImage: "bookmark.fill") {
            QuickCaptureMenu(model: model)
        }
        Settings {
            NavigationStack { SettingsView() }
        }
        #endif
    }
}
