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

/// What a capture surface collected, before the user picks an intent.
public struct SharedContent: Sendable, Equatable {
    public var url: URL?
    public var title: String?
    public var text: String?
    public var selection: TextQuote?
    public var page: PageContext?
    public var files: [PayloadFile]
    public var sourceApp: String?

    public init(
        url: URL? = nil,
        title: String? = nil,
        text: String? = nil,
        selection: TextQuote? = nil,
        page: PageContext? = nil,
        files: [PayloadFile] = [],
        sourceApp: String? = nil
    ) {
        self.url = url
        self.title = title
        self.text = text
        self.selection = selection
        self.page = page
        self.files = files
        self.sourceApp = sourceApp
    }

    public var isEmpty: Bool {
        url == nil && (text?.isEmpty ?? true) && selection == nil && files.isEmpty
    }

    public mutating func apply(_ page: PageCapture) {
        url = url ?? page.url
        title = page.title ?? title
        selection = page.selection ?? selection
        self.page = PageContext(
            canonicalURL: page.canonicalURL,
            language: page.language,
            excerpt: page.excerpt,
            jsonLD: page.jsonLD
        )
    }

    /// Text that is just a web link (common from apps that share or copy "text")
    /// becomes the URL.
    public mutating func promoteLinkText() {
        guard url == nil, let text, let link = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              link.scheme == "http" || link.scheme == "https", link.host() != nil
        else { return }
        url = link
        self.text = nil
    }

    /// A shared file has no title of its own; its name is the best one ("Q3 report").
    public mutating func useFileNameAsTitle() {
        guard title?.isEmpty ?? true, url == nil, let name = files.first?.displayName else { return }
        title = name
    }

    /// Text selected on a page whose URL is known is a highlight: it gets a text
    /// fragment anchor so opening the item scrolls to it (PRD C4, F5).
    public mutating func quoteTextFromPage() {
        guard url != nil, selection == nil, let text, !text.isEmpty else { return }
        selection = TextQuote(exact: text)
        self.text = nil
    }

    public mutating func appendText(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = text.map { $0 + "\n\n" + trimmed } ?? trimmed
    }
}

/// The dictionary produced by `PageCapture.js` (share extension preprocessing)
/// and by the Safari extension's content script. Both use the same keys.
public struct PageCapture: Sendable, Equatable {
    public var url: URL?
    public var title: String?
    public var selection: TextQuote?
    public var language: String?
    public var canonicalURL: URL?
    public var excerpt: String?
    public var jsonLD: [String]

    public init(dictionary: [String: Any]) {
        url = (dictionary["url"] as? String).flatMap { URL(string: $0) }
        title = Self.nonEmpty(dictionary["title"])
        language = Self.nonEmpty(dictionary["lang"])
        canonicalURL = (dictionary["canonical"] as? String).flatMap { URL(string: $0) }
        excerpt = Self.nonEmpty(dictionary["excerpt"])
        jsonLD = dictionary["jsonLD"] as? [String] ?? []
        if let selection = dictionary["selection"] as? [String: Any], let exact = Self.nonEmpty(selection["exact"]) {
            self.selection = TextQuote(
                exact: exact,
                prefix: Self.nonEmpty(selection["prefix"]),
                suffix: Self.nonEmpty(selection["suffix"])
            )
        } else {
            selection = nil
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }
}

extension CaptureEnvelope {
    public init(
        id: ULID,
        content: SharedContent,
        surface: CaptureSurface,
        intent: Intent?,
        note: String?,
        device: String,
        capturedAt: Date = Date()
    ) {
        self.init(
            id: id,
            capturedAt: capturedAt,
            device: device,
            surface: surface,
            sourceApp: content.sourceApp,
            url: content.url,
            title: content.title,
            selection: content.selection,
            text: content.text,
            pageContext: content.page,
            payloadFiles: content.files,
            userIntent: intent,
            userNote: note
        )
    }
}

/// The one-call path every capture surface uses.
public enum CaptureWriter {
    public static func commit(
        _ content: SharedContent,
        id: ULID = ULID(),
        surface: CaptureSurface,
        intent: Intent? = nil,
        note: String? = nil,
        store: EnvelopeStore = EnvelopeStore(),
        device: String = DeviceIdentity.current()
    ) throws {
        let envelope = CaptureEnvelope(
            id: id, content: content, surface: surface, intent: intent, note: note, device: device
        )
        try store.commit(envelope)
    }
}
