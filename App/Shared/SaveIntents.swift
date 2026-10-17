//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//


import AppIntents
import Foundation
import Model
import Capture
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Saves a link or text to Laterwise from Shortcuts: an action to chain after "Get
/// Clipboard", or "Get URLs from Input" in a share-sheet shortcut.
struct SaveToLaterwiseIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Laterwise"
    static let description = IntentDescription("Saves a link or some text to your Laterwise Inbox, as if you had shared it.")

    @Parameter(title: "Link or Text")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try SaveIntents.save(text)
        return .result(dialog: "Saved to Laterwise.")
    }
}

/// Saves what's on the clipboard: for Back Tap, the Action Button or Siri ("Save
/// clipboard to Laterwise") after "Copy Link" in a shopping app with no Share menu.
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard to Laterwise"
    static let description = IntentDescription("Saves the link or text you copied to your Laterwise Inbox.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let text = SaveIntents.clipboardText() else {
            return .result(dialog: "There's nothing on the clipboard to save. Copy a link first.")
        }
        try SaveIntents.save(text)
        return .result(dialog: "Saved to Laterwise.")
    }
}

enum SaveIntents {
    /// A capture like one from the Share menu; the app adds it to the library.
    static func save(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var content = SharedContent()
        content.appendText(trimmed)
        content.promoteLinkText()
        try CaptureWriter.commit(content, surface: .appIntent)
    }

    @MainActor
    static func clipboardText() -> String? {
        #if os(iOS)
        let board = UIPasteboard.general
        return board.url?.absoluteString ?? board.string
        #else
        let board = NSPasteboard.general
        return board.string(forType: .URL) ?? board.string(forType: .string)
        #endif
    }
}

struct LaterwiseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveClipboardIntent(),
            phrases: [
                "Save clipboard to \(.applicationName)",
                "Save copied link to \(.applicationName)",
            ],
            shortTitle: "Save Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
