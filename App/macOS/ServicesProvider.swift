//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

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
        let snapshot = PasteboardCapture.snapshot(of: pasteboard)
        guard !snapshot.isEmpty else {
            errorPointer.pointee = NSString(string: String(localized: "There was nothing to save."))
            return
        }
        // The app that asked for the service is still frontmost.
        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let store = store
        // Answer the requesting app now: it waits for this reply, and copying large
        // files can take longer than it will wait. The outcome shows in the HUD.
        Task {
            var content = await PasteboardCapture.content(from: snapshot, id: id, store: store)
            content.sourceApp = sourceApp
            // Text selected on a web page (the browser sends the page URL along) is a highlight.
            content.quoteTextFromPage()
            guard !content.isEmpty else {
                try? store.discard(id)
                SavedHUD.show(String(localized: "There was nothing to save."), systemImage: "exclamationmark.triangle.fill")
                return
            }
            do {
                try CaptureWriter.commit(content, id: id, surface: .services, store: store)
                SavedHUD.show(String(localized: "Saved to Nextmark"))
            } catch {
                try? store.discard(id)
                SavedHUD.show(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }
}
