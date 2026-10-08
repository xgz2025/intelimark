import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Right-click → Services → Save to Nextmark (PRD C4).
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
    }
}
