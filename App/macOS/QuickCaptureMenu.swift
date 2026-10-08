import AppKit
import SwiftUI
import Model
import Capture

/// The menu-bar extra (PRD C5). The global hotkey and screenshot capture come next.
struct QuickCaptureMenu: View {
    let model: AppModel

    var body: some View {
        Button("Save Clipboard") { saveClipboard() }
        Divider()
        Button("Quit Nextmark") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func saveClipboard() {
        let content = PasteboardCapture.content(from: .general)
        guard !content.isEmpty else { return }
        try? CaptureWriter.commit(content, surface: .quickCapture, store: model.store)
    }
}
