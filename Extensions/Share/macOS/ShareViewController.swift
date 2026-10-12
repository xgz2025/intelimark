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
import SwiftUI
import Model
import Capture
import CaptureUI

/// macOS share extension (PRD C3): right-click → Share → Nextmark in Safari,
/// Finder, Photos, Preview and Notes. Same flow as iOS.
final class ShareViewController: NSViewController {
    private let store = EnvelopeStore()
    private let captureID = ULID()
    private let draft = CaptureDraft()

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let sheet = CaptureSheet(
            draft: draft,
            onSave: { [weak self] in self?.save() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let hosting = NSHostingView(rootView: sheet)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 380)
        view = hosting
        preferredContentSize = hosting.frame.size
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await loadContent() }
    }

    private func loadContent() async {
        let inputItems = extensionContext?.inputItems ?? []
        do {
            let payloadDirectory = try store.makePayloadDirectory(for: captureID)
            draft.content = await ShareItemLoader.load(inputItems: inputItems, payloadDirectory: payloadDirectory)
        } catch {
            // Without the shared folder nothing can reach the app; say so rather than pretend.
            draft.error = String(localized: "Nextmark can't save right now: \(error.localizedDescription)")
        }
        draft.isLoading = false
    }

    private func save() {
        guard let content = draft.content else { return }
        do {
            try CaptureWriter.commit(
                content, id: captureID, surface: .shareSheet,
                intent: draft.intent, note: draft.trimmedNote, store: store
            )
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            // Closing the sheet would look like a successful save: keep it open and say why.
            draft.error = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }

    private func cancel() {
        try? store.discard(captureID)
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
