import Foundation

/// A W3C-style text quote selector: the selected text plus a little context on
/// each side, so a highlight can be found again when the page changes slightly.
public struct TextQuote: Codable, Sendable, Hashable {
    public var exact: String
    public var prefix: String?
    public var suffix: String?

    public init(exact: String, prefix: String? = nil, suffix: String? = nil) {
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
    }
}

/// A rectangle in unit coordinates (0...1) relative to an image or page.
public struct NormalizedRect: Codable, Sendable, Hashable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// How to return to the exact place something was saved from (PRD F5).
public enum SelectionAnchor: Codable, Sendable, Hashable {
    /// `textFragmentURL` opens the page scrolled to the quote.
    case web(textFragmentURL: URL, quote: TextQuote)
    case pdf(page: Int, quote: TextQuote?)
    /// `message://<Message-ID>` from Mail on the Mac.
    case mail(messageURL: URL)
    /// Security-scoped bookmark (Mac) to a file outside the container.
    case file(bookmark: Data, quote: TextQuote?)
    case image(region: NormalizedRect?)
}
