import Foundation

/// Small, dependency-free HTML helpers. Not a full parser: tolerant regular
/// expressions are enough for metadata and readable text, and keep the module
/// usable on every platform (iOS has no `XMLDocument`).
enum HTMLText {
    static let blockOptions: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

    static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure is a programming error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: blockOptions)
    }

    /// All matches of `pattern`, each as its capture groups (index 0 = whole match).
    static func matches(_ regex: NSRegularExpression, in text: String) -> [[String?]] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }

    static func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    // MARK: Attributes

    static let attributePattern = regex(
        #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
    )

    /// Attributes of a single start tag, keys lowercased, values entity-decoded.
    static func attributes(of tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for groups in matches(attributePattern, in: tag) {
            guard let name = groups[1]?.lowercased() else { continue }
            let value = groups[2] ?? groups[3] ?? groups[4] ?? ""
            if result[name] == nil { result[name] = decodeEntities(value) }
        }
        return result
    }

    // MARK: Entities

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "middot": "·", "bull": "•",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "euro": "€", "pound": "£", "yen": "¥",
        "times": "×", "eacute": "é", "egrave": "è", "ecirc": "ê", "aacute": "á", "agrave": "à",
        "acirc": "â", "auml": "ä", "ouml": "ö", "uuml": "ü", "szlig": "ß", "ccedil": "ç",
        "ntilde": "ñ", "iacute": "í", "oacute": "ó", "uacute": "ú",
    ]

    static let entityPattern = regex(#"&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});"#)

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var cursor = text.startIndex
        let range = NSRange(text.startIndex..., in: text)
        for match in entityPattern.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            result += text[cursor..<whole.lowerBound]
            let name = String(text[nameRange])
            if let replacement = decodeEntity(name) {
                result += replacement
            } else {
                result += text[whole]
            }
            cursor = whole.upperBound
        }
        result += text[cursor...]
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            return value.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        return namedEntities[name] ?? namedEntities[name.lowercased()]
    }

    /// Collapses runs of whitespace to single spaces and trims.
    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Truncates at a word boundary.
    static func truncate(_ text: String, to maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let cut = text.prefix(maxCharacters)
        let boundary = cut.lastIndex(where: { $0.isWhitespace }) ?? cut.endIndex
        return String(cut[..<boundary])
    }
}
