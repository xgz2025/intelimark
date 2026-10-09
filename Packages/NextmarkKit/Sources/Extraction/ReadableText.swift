import Foundation

/// A small readability pass: drops chrome (navigation, scripts, footers), prefers
/// the largest `<article>`, then `<main>`, then `<body>`, and keeps paragraph breaks.
public enum ReadableText {
    public static let defaultMaxCharacters = 20_000

    nonisolated(unsafe) static let comments = HTMLText.regex(#"<!--.*?-->"#)
    nonisolated(unsafe) static let chrome = HTMLText.regex(
        #"<(script|style|noscript|svg|template|iframe|nav|header|footer|aside|form|button|select|figure)\b[^>]*>.*?</\1\s*>"#
    )
    nonisolated(unsafe) static let article = HTMLText.regex(#"<article\b[^>]*>(.*?)</article\s*>"#)
    nonisolated(unsafe) static let main = HTMLText.regex(#"<main\b[^>]*>(.*?)</main\s*>"#)
    nonisolated(unsafe) static let body = HTMLText.regex(#"<body\b[^>]*>(.*?)(?:</body\s*>|$)"#)
    nonisolated(unsafe) static let listItem = HTMLText.regex(#"<li\b[^>]*>"#)
    nonisolated(unsafe) static let blockBreak = HTMLText.regex(
        #"<(?:br|hr)\b[^>]*>|</(?:p|div|li|h[1-6]|tr|section|blockquote|pre|dd|dt|table|ul|ol)\s*>|<(?:p|h[1-6]|tr|blockquote|pre)\b[^>]*>"#
    )
    nonisolated(unsafe) static let anyTag = HTMLText.regex(#"<[^>]+>"#)

    public static func extract(fromHTML html: String, maxCharacters: Int = defaultMaxCharacters) -> String? {
        var text = HTMLText.replacing(comments, in: html, with: " ")
        text = HTMLText.replacing(chrome, in: text, with: " ")

        let articles = HTMLText.matches(article, in: text).compactMap { $0[1] }
        if let largest = articles.max(by: { $0.count < $1.count }) {
            text = largest
        } else if let mainContent = HTMLText.matches(main, in: text).first?[1] {
            text = mainContent
        } else if let bodyContent = HTMLText.matches(body, in: text).first?[1] {
            text = bodyContent
        }

        text = HTMLText.replacing(listItem, in: text, with: "\n• ")
        text = HTMLText.replacing(blockBreak, in: text, with: "\n")
        text = HTMLText.replacing(anyTag, in: text, with: " ")
        text = HTMLText.decodeEntities(text)

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { HTMLText.collapseWhitespace(String($0)) }
            .filter { $0.count > 1 }
        guard !lines.isEmpty else { return nil }
        return HTMLText.truncate(lines.joined(separator: "\n"), to: maxCharacters)
    }
}
