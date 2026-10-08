import Foundation
import SafariServices
import Model
import Capture

/// Native side of the Safari Web Extension (PRD C7). `background.js` sends
/// `{type: "save", …page capture…}` via `browser.runtime.sendNativeMessage`.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let saved = (message["type"] as? String) == "save" && save(message)

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": saved]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func save(_ message: [String: Any]) -> Bool {
        var content = SharedContent()
        content.apply(PageCapture(dictionary: message))
        content.sourceApp = "com.apple.Safari"
        guard !content.isEmpty else { return false }
        do {
            try CaptureWriter.commit(content, surface: .safariExtension)
            return true
        } catch {
            return false
        }
    }
}
