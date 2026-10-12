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
import UniformTypeIdentifiers
import Model
import Capture

/// Reads a pasteboard (the clipboard, a Services request, a drop) into capture
/// content. Files and images are copied into the capture's payload directory.
@MainActor
enum PasteboardCapture {
    static func content(from pasteboard: NSPasteboard, id: ULID, store: EnvelopeStore) -> SharedContent {
        var content = SharedContent()

        let fileURLs = urls(on: pasteboard, fileURLsOnly: true)
        for (index, url) in fileURLs.enumerated() {
            if let file = try? store.addPayloadFile(copying: url, for: id, index: index) {
                content.files.append(file)
            }
        }
        if fileURLs.isEmpty, let png = imageData(on: pasteboard),
           let file = try? store.addPayload(png, fileName: "0-image.png", contentType: .png, for: id) {
            content.files.append(file)
        }

        content.url = urls(on: pasteboard, fileURLsOnly: false).first { !$0.isFileURL }
        // Finder puts file names on the pasteboard as text too, and browsers the link
        // itself; neither is worth keeping as text.
        if fileURLs.isEmpty, let text = pasteboard.string(forType: .string),
           text.trimmingCharacters(in: .whitespacesAndNewlines) != content.url?.absoluteString {
            content.appendText(text)
        }
        content.promoteLinkText()
        content.useFileNameAsTitle()
        return content
    }

    private static func urls(on pasteboard: NSPasteboard, fileURLsOnly: Bool) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = fileURLsOnly ? [.urlReadingFileURLsOnly: true] : [:]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []).compactMap { $0 as? URL }
    }

    /// PNG, or TIFF converted to PNG (what most apps put on the pasteboard for images).
    private static func imageData(on pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
