//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

#if canImport(UniformTypeIdentifiers)
import Foundation
import UniformTypeIdentifiers
import Model

/// Turns a share extension's `NSExtensionItem`s into `SharedContent`, copying files
/// into the capture's payload directory. Runs no AI and keeps memory low: the share
/// extension must commit in well under a second (Docs/architecture.md §2).
///
/// The `NSItemProvider` callbacks arrive on background queues, so each one is wrapped
/// in a nonisolated helper with a `@Sendable` completion and resumed from the main actor.
public enum ShareItemLoader {
    @MainActor
    public static func load(inputItems: [Any], payloadDirectory: URL) async -> SharedContent {
        var content = SharedContent()
        var fileIndex = 0
        for case let item as NSExtensionItem in inputItems {
            if content.title == nil, let title = item.attributedTitle?.string, !title.isEmpty {
                content.title = title
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    let page = await withCheckedContinuation { continuation in
                        loadPage(from: provider) { continuation.resume(returning: $0) }
                    }
                    if let page { content.apply(page) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let url = await withCheckedContinuation { continuation in
                        loadURL(from: provider) { continuation.resume(returning: $0) }
                    }
                    if content.url == nil { content.url = url }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !isFile(provider) {
                    let text = await withCheckedContinuation { continuation in
                        loadText(from: provider) { continuation.resume(returning: $0) }
                    }
                    if let text { content.appendText(String(text.prefix(maxInlineTextCharacters))) }
                } else if let typeIdentifier = fileTypeIdentifier(of: provider) {
                    let index = fileIndex
                    let file = await withCheckedContinuation { continuation in
                        copyFile(from: provider, typeIdentifier: typeIdentifier, to: payloadDirectory, index: index) {
                            continuation.resume(returning: $0)
                        }
                    }
                    if let file {
                        content.files.append(file)
                        fileIndex += 1
                    }
                }
            }
        }
        content.promoteLinkText()
        content.useFileNameAsTitle()
        return content
    }

    /// Shared text longer than this is cut; a text *file* is copied, never read into memory.
    static let maxInlineTextCharacters = 100_000

    /// A shared document (a .txt or source file from Files or Finder) rather than a
    /// snippet of text: it has a file name.
    static func isFile(_ provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return true }
        // A name like "notes.txt", not text that happens to contain a dot ("v1.2 notes").
        guard let name = provider.suggestedName else { return false }
        let pathExtension = (name as NSString).pathExtension
        return !pathExtension.isEmpty && UTType(filenameExtension: pathExtension).map { !$0.isDynamic } == true
    }

    static func loadPage(from provider: NSItemProvider, completion: @escaping @Sendable (PageCapture?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, _ in
            guard
                let dictionary = item as? NSDictionary,
                let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
            else {
                completion(nil)
                return
            }
            completion(PageCapture(dictionary: results))
        }
    }

    static func loadURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in completion(url) }
    }

    static func loadText(from provider: NSItemProvider, completion: @escaping @Sendable (String?) -> Void) {
        _ = provider.loadObject(ofClass: String.self) { text, _ in completion(text) }
    }

    static func fileTypeIdentifier(of provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first {
            $0 != UTType.fileURL.identifier && $0 != UTType.url.identifier
        }
    }

    static func copyFile(
        from provider: NSItemProvider,
        typeIdentifier: String,
        to directory: URL,
        index: Int,
        completion: @escaping @Sendable (PayloadFile?) -> Void
    ) {
        _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
            // The temporary file only exists until this handler returns: copy synchronously.
            guard let url else {
                completion(nil)
                return
            }
            let fileName = "\(index)-\(url.lastPathComponent)"
            let destination = directory.appending(path: fileName)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
                completion(PayloadFile(fileName: fileName, contentType: typeIdentifier, byteSize: size.map { Int64($0) }))
            } catch {
                completion(nil)
            }
        }
    }
}
#endif
