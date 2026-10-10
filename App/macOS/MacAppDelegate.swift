import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Right-click → Services → Save to Nextmark (PRD C4).
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
