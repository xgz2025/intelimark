#if canImport(PDFKit)
import Foundation
import PDFKit

/// Text from a PDF, page by page, for search and the Understand stage (PRD U1).
public enum PDFText {
    public static let defaultMaxCharacters = 30_000

    public static func extract(from url: URL, maxCharacters: Int = defaultMaxCharacters) -> String? {
        PDFDocument(url: url).flatMap { extract(from: $0, maxCharacters: maxCharacters) }
    }

    public static func extract(from data: Data, maxCharacters: Int = defaultMaxCharacters) -> String? {
        PDFDocument(data: data).flatMap { extract(from: $0, maxCharacters: maxCharacters) }
    }

    static func extract(from document: PDFDocument, maxCharacters: Int) -> String? {
        var pages: [String] = []
        var length = 0
        for index in 0..<document.pageCount {
            guard length < maxCharacters, let text = document.page(at: index)?.string else { continue }
            let cleaned = text
                .split(whereSeparator: \.isNewline)
                .map { HTMLText.collapseWhitespace(String($0)) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !cleaned.isEmpty else { continue }
            pages.append(cleaned)
            length += cleaned.count
        }
        guard !pages.isEmpty else { return nil }
        return HTMLText.truncate(pages.joined(separator: "\n\n"), to: maxCharacters)
    }
}
#endif
