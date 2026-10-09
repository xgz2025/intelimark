import Foundation

/// What a page says about itself in its `<head>` and JSON-LD blocks.
public struct HTMLMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var siteName: String?
    public var language: String?
    public var canonicalURL: URL?
    public var imageURL: URL?
    public var jsonLD: [String]

    public init(
        title: String? = nil, description: String? = nil, siteName: String? = nil, language: String? = nil,
        canonicalURL: URL? = nil, imageURL: URL? = nil, jsonLD: [String] = []
    ) {
        self.title = title
        self.description = description
        self.siteName = siteName
        self.language = language
        self.canonicalURL = canonicalURL
        self.imageURL = imageURL
        self.jsonLD = jsonLD
    }
}

public enum HTMLParser {
    static let maxJSONLDBlocks = 10
    static let maxJSONLDCharacters = 100_000

    nonisolated(unsafe) static let metaTag = HTMLText.regex(#"<meta\b[^>]*>"#)
    nonisolated(unsafe) static let linkTag = HTMLText.regex(#"<link\b[^>]*>"#)
    nonisolated(unsafe) static let htmlTag = HTMLText.regex(#"<html\b[^>]*>"#)
    nonisolated(unsafe) static let titleElement = HTMLText.regex(#"<title\b[^>]*>(.*?)</title>"#)
    nonisolated(unsafe) static let scriptElement = HTMLText.regex(#"<script\b([^>]*)>(.*?)</script>"#)

    /// Relative URLs (images, canonical) are resolved against `baseURL`.
    public static func metadata(from html: String, baseURL: URL?) -> HTMLMetadata {
        var meta: [String: String] = [:]
        for groups in HTMLText.matches(metaTag, in: html) {
            guard let tag = groups[0] else { continue }
            let attributes = HTMLText.attributes(of: tag)
            guard let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased(),
                  let content = attributes["content"].map(HTMLText.collapseWhitespace), !content.isEmpty,
                  meta[key] == nil
            else { continue }
            meta[key] = content
        }

        var canonical: URL?
        for groups in HTMLText.matches(linkTag, in: html) {
            guard let tag = groups[0] else { continue }
            let attributes = HTMLText.attributes(of: tag)
            let rel = attributes["rel"]?.lowercased().split(separator: " ") ?? []
            if rel.contains("canonical"), let href = attributes["href"] {
                canonical = resolve(href, against: baseURL)
                break
            }
        }

        let documentTitle = HTMLText.matches(titleElement, in: html).first?[1]
            .map { HTMLText.collapseWhitespace(HTMLText.decodeEntities($0)) }
        let language = HTMLText.matches(htmlTag, in: html).first?[0]
            .flatMap { HTMLText.attributes(of: $0)["lang"] }

        return HTMLMetadata(
            title: nonEmpty(meta["og:title"] ?? documentTitle ?? meta["twitter:title"]),
            description: nonEmpty(meta["og:description"] ?? meta["description"] ?? meta["twitter:description"]),
            siteName: nonEmpty(meta["og:site_name"] ?? meta["application-name"]),
            language: nonEmpty(language),
            canonicalURL: canonical ?? meta["og:url"].flatMap { resolve($0, against: baseURL) },
            imageURL: (meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"]).flatMap { resolve($0, against: baseURL) },
            jsonLD: jsonLDBlocks(in: html)
        )
    }

    static func jsonLDBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        for groups in HTMLText.matches(scriptElement, in: html) {
            guard blocks.count < maxJSONLDBlocks,
                  let attributeText = groups[1], let body = groups[2],
                  HTMLText.attributes(of: "<script \(attributeText)>")["type"]?.lowercased() == "application/ld+json"
            else { continue }
            var json = body.trimmingCharacters(in: .whitespacesAndNewlines)
            for wrapper in ["<!--", "-->", "//<![CDATA[", "//]]>", "<![CDATA[", "]]>"] {
                json = json.replacingOccurrences(of: wrapper, with: "")
            }
            json = json.trimmingCharacters(in: .whitespacesAndNewlines)
            if !json.isEmpty { blocks.append(String(json.prefix(maxJSONLDCharacters))) }
        }
        return blocks
    }

    static func resolve(_ reference: String, against baseURL: URL?) -> URL? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "http" || url.scheme == "https"
        else { return nil }
        return url
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
