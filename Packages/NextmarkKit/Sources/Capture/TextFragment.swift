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
import Model

/// Builds URL text fragments (`#:~:text=`) so opening a saved highlight scrolls
/// Safari straight to it. https://wicg.github.io/scroll-to-text-fragment/
public enum TextFragment {
    /// Quotes longer than this many words are encoded as `start,end` instead of in full.
    static let maxInlineWords = 8
    static let edgeWords = 4
    static let contextWords = 3

    public static func url(for pageURL: URL, quote: TextQuote) -> URL? {
        let words = normalizedWords(quote.exact)
        guard !words.isEmpty else { return nil }

        var parts: [String] = []
        if let prefix = quote.prefix.map(normalizedWords), !prefix.isEmpty {
            parts.append(encode(prefix.suffix(contextWords).joined(separator: " ")) + "-")
        }
        if words.count > maxInlineWords {
            parts.append(encode(words.prefix(edgeWords).joined(separator: " ")))
            parts.append(encode(words.suffix(edgeWords).joined(separator: " ")))
        } else {
            parts.append(encode(words.joined(separator: " ")))
        }
        if let suffix = quote.suffix.map(normalizedWords), !suffix.isEmpty {
            parts.append("-" + encode(suffix.prefix(contextWords).joined(separator: " ")))
        }

        var base = pageURL.absoluteString
        if let range = base.range(of: ":~:") {
            base = String(base[..<range.lowerBound])          // replace an existing directive
        }
        let separator = base.contains("#") ? ":~:text=" : "#:~:text="
        return URL(string: base + separator + parts.joined(separator: ","))
    }

    static func normalizedWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Percent-encodes everything except unreserved ASCII, which also covers the
    /// characters that are syntax inside a text directive (`-`, `,`, `&`).
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~"
    )
}
