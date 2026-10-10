import AppKit
import SwiftUI

/// A brief confirmation near the top of the screen after a save from Services, the
/// menu bar or the hotkey, which otherwise happen without any window. It never takes
/// focus or clicks, and VoiceOver announces it.
@MainActor
enum SavedHUD {
    private static var panel: NSPanel?
    private static var dismissal: Task<Void, Never>?

    static func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        dismissal?.cancel()
        let panel = Self.panel ?? makePanel()
        Self.panel = panel
        panel.contentView = NSHostingView(rootView: HUDView(message: message, systemImage: systemImage))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 240, height: 44))
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        dismissal = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            panel.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    /// Centered horizontally, just below the menu bar of the screen under the pointer.
    private static func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24))
    }
}

private struct HUDView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.headline)
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .padding(8)            // room for the shadow
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .fixedSize()
    }
}
