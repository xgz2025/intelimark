//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import Foundation
import UniformTypeIdentifiers
import Model
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The text, title and author of a Word document (`.docx`) or a rich-text file
/// (`.rtf`), so an article saved as one reads like any other.
public enum DocumentText {
    static let wordType = "org.openxmlformats.wordprocessingml.document"

    public static func canRead(_ type: UTType?, fileName: String) -> Bool {
        isWord(type, fileName: fileName) || isRichText(type)
    }

    static func isWord(_ type: UTType?, fileName: String) -> Bool {
        let word = UTType(wordType)
        return type?.identifier == wordType || (word.map { type?.conforms(to: $0) == true } ?? false)
            || fileName.lowercased().hasSuffix(".docx")
    }

    static func isRichText(_ type: UTType?) -> Bool {
        type?.conforms(to: .rtf) == true || type?.conforms(to: .rtfd) == true
    }

    /// The document's text (cut to `limit`) and its own title, author and date.
    public static func read(_ url: URL, type: UTType?, limit: Int) -> (text: String?, fields: ArticleFields?) {
        if isWord(type, fileName: url.lastPathComponent) {
            guard let archive = ZipArchive(url: url) else { return (nil, nil) }
            let text = archive.contents(of: "word/document.xml").map { wordText(String(decoding: $0, as: UTF8.self)) }
            let fields = archive.contents(of: "docProps/core.xml").flatMap { coreProperties(String(decoding: $0, as: UTF8.self)) }
            return (text.map { HTMLText.truncate($0, to: limit) }.flatMap(nonEmpty), fields)
        }
        if isRichText(type) {
            return (richText(url).map { HTMLText.truncate($0, to: limit) }.flatMap(nonEmpty), nil)
        }
        return (nil, nil)
    }

    /// `word/document.xml`: paragraphs (`w:p`) of runs of text (`w:t`).
    static func wordText(_ xml: String) -> String {
        var text = xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "<w:tab/>", with: "\t")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let lines = HTMLText.decodeEntities(text)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// `docProps/core.xml`: `dc:title`, `dc:creator`, `dcterms:created`.
    static func coreProperties(_ xml: String) -> ArticleFields? {
        func element(_ name: String) -> String? {
            guard let range = xml.range(of: "<\(name)[^>]*>([^<]*)</\(name)>", options: .regularExpression) else { return nil }
            let inner = xml[range].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let value = HTMLText.decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let title = element("dc:title").flatMap { PDFMetadataTitle.isPlaceholder($0) ? nil : $0 }
        let fields = ArticleFields(
            headline: title,
            author: element("dc:creator"),
            publishedAt: element("dcterms:created").flatMap { SchemaDate.parse($0) }
        )
        return fields.headline == nil && fields.author == nil ? nil : fields
    }

    static func richText(_ url: URL) -> String? {
        #if canImport(UIKit) || canImport(AppKit)
        let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "rtfd" ? .rtfd : .rtf
        let string = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
        return string
        #else
        return nil
        #endif
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Titles that tools fill in on their own, shared by PDFs and Word documents.
enum PDFMetadataTitle {
    static func isPlaceholder(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("microsoft word - ") || lowered == "untitled" || lowered.hasSuffix(".docx")
            || lowered.hasSuffix(".doc") || lowered.hasSuffix(".pdf")
    }
}
