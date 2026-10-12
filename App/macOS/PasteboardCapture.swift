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
/// content. Reading the pasteboard is quick and happens on the main actor; copying
/// files and converting images can take long (a large video, a file on a slow disk),
/// so it happens off it.
enum PasteboardCapture {
    /// What was on the pasteboard, taken off it at once.
    struct Snapshot: Sendable {
        var fileURLs: [URL] = []
        var url: URL?
        var text: String?
        var png: Data?
        var tiff: Data?

        var isEmpty: Bool {
            fileURLs.isEmpty && url == nil && png == nil && tiff == nil
                && (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    @MainActor
    static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.fileURLs = urls(on: pasteboard, fileURLsOnly: true)
        snapshot.url = urls(on: pasteboard, fileURLsOnly: false).first { !$0.isFileURL }
        if snapshot.fileURLs.isEmpty {
            snapshot.png = pasteboard.data(forType: .png)
            if snapshot.png == nil { snapshot.tiff = pasteboard.data(forType: .tiff) }
            snapshot.text = pasteboard.string(forType: .string)
        }
        return snapshot
    }

    static func content(from snapshot: Snapshot, id: ULID, store: EnvelopeStore) async -> SharedContent {
        await Task.detached(priority: .userInitiated) {
            Self.content(from: snapshot, id: id, store: store)
        }.value
    }

    /// Copies files and converts images into the capture's payload directory.
    static func content(from snapshot: Snapshot, id: ULID, store: EnvelopeStore) -> SharedContent {
        var content = SharedContent()
        for url in snapshot.fileURLs where !isDirectory(url) {
            if let file = try? store.addPayloadFile(copying: url, for: id, index: content.files.count) {
                content.files.append(file)
            }
        }
        if snapshot.fileURLs.isEmpty, let png = snapshot.png ?? snapshot.tiff.flatMap(pngFromTIFF),
           let file = try? store.addPayload(png, fileName: "0-image.png", contentType: .png, for: id) {
            content.files.append(file)
        }

        content.url = snapshot.url
        // Finder puts file names on the pasteboard as text too, and browsers the link
        // itself; neither is worth keeping as text.
        if let text = snapshot.text, text.trimmingCharacters(in: .whitespacesAndNewlines) != content.url?.absoluteString {
            content.appendText(String(text.prefix(maxTextCharacters)))
        }
        content.promoteLinkText()
        content.useFileNameAsTitle()
        return content
    }

    /// Longer text is cut: a whole book copied by mistake shouldn't become one item.
    static let maxTextCharacters = 100_000

    /// Folders aren't saved: copying one could take as long as the disk is big.
    /// Documents stored as packages (.rtfd, Pages, Keynote) are files to the person, and are saved.
    static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    @MainActor
    private static func urls(on pasteboard: NSPasteboard, fileURLsOnly: Bool) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = fileURLsOnly ? [.urlReadingFileURLsOnly: true] : [:]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []).compactMap { $0 as? URL }
    }

    /// Most apps put images on the pasteboard as TIFF.
    private static func pngFromTIFF(_ tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
