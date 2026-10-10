import AppKit
import Model
import Capture

/// Handles right-click → Services → Save to Nextmark (PRD C4), declared under
/// NSServices in Info.plist: selected text and links in any app, and files in
/// Finder. The selector name must match NSMessage (`saveSelection`).
@MainActor
final class ServicesProvider: NSObject {
    private let store: EnvelopeStore

    init(store: EnvelopeStore = EnvelopeStore()) {
        self.store = store
    }

    @objc func saveSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let id = ULID()
        var content = PasteboardCapture.content(from: pasteboard, id: id, store: store)
        // The app that asked for the service is still frontmost.
        content.sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Text selected on a web page (the browser sends the page URL along) is a highlight.
        content.quoteTextFromPage()
        guard !content.isEmpty else {
            try? store.discard(id)
            errorPointer.pointee = NSString(string: String(localized: "There was nothing to save."))
            return
        }
        do {
            try CaptureWriter.commit(content, id: id, surface: .services, store: store)
            SavedHUD.show(String(localized: "Saved to Nextmark"))
        } catch {
            try? store.discard(id)
            errorPointer.pointee = NSString(string: error.localizedDescription)
        }
    }
}
