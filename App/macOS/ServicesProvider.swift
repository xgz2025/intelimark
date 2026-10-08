import AppKit
import Model
import Capture

/// Handles the "Save to Nextmark" service declared under NSServices in Info.plist.
/// The selector name must match NSMessage (`saveSelection`).
@MainActor
final class ServicesProvider: NSObject {
    @objc func saveSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        var content = PasteboardCapture.content(from: pasteboard)
        content.sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !content.isEmpty else {
            errorPointer.pointee = NSString(string: String(localized: "There was nothing to save."))
            return
        }
        do {
            try CaptureWriter.commit(content, surface: .services)
        } catch {
            errorPointer.pointee = NSString(string: error.localizedDescription)
        }
    }
}

enum PasteboardCapture {
    @MainActor
    static func content(from pasteboard: NSPasteboard) -> SharedContent {
        var content = SharedContent()
        if let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, !url.isFileURL {
            content.url = url
        }
        if let text = pasteboard.string(forType: .string) {
            if content.url == nil, let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
                content.url = url
            } else {
                content.appendText(text)
            }
        }
        return content
    }
}
