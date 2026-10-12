//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import SwiftUI
import UIKit
import Model
import Capture
import CaptureUI

/// iOS share extension (PRD C1): collect → choose intent → commit an envelope → done.
/// No AI and no database access here (Docs/architecture.md §2).
final class ShareViewController: UIViewController {
    private let store = EnvelopeStore()
    private let captureID = ULID()
    private let draft = CaptureDraft()

    override func viewDidLoad() {
        super.viewDidLoad()
        let sheet = CaptureSheet(
            draft: draft,
            onSave: { [weak self] in self?.save() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: sheet)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

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
