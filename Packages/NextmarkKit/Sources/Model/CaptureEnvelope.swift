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

/// Page details captured by the Safari preprocessing script or the Safari extension.
public struct PageContext: Codable, Sendable, Hashable {
    public var canonicalURL: URL?
    public var language: String?
    public var excerpt: String?
    /// Raw schema.org JSON-LD blocks, parsed later by the Extract stage.
    public var jsonLD: [String]

    public init(canonicalURL: URL? = nil, language: String? = nil, excerpt: String? = nil, jsonLD: [String] = []) {
        self.canonicalURL = canonicalURL
        self.language = language
        self.excerpt = excerpt
        self.jsonLD = jsonLD
    }
}

/// A file copied into the envelope's `payload/` directory.
public struct PayloadFile: Codable, Sendable, Hashable {
    public var fileName: String
    /// Uniform Type Identifier, e.g. `public.jpeg`.
    public var contentType: String
    public var byteSize: Int64?

    public init(fileName: String, contentType: String, byteSize: Int64? = nil) {
        self.fileName = fileName
        self.contentType = contentType
        self.byteSize = byteSize
    }

    /// The file's own name as a title ("Q3 report" for `0-Q3 report.pdf`), or nil
    /// when the name says nothing (camera roll names, "image").
    public var displayName: String? {
        var name = fileName
        // Payload files are stored as "<index>-<original name>".
        if let dash = name.firstIndex(of: "-"), dash != name.startIndex, name[..<dash].allSatisfy(\.isNumber) {
            name = String(name[name.index(after: dash)...])
        }
        name = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !Self.meaninglessNames.contains(name.lowercased()),
              name.range(of: #"^(IMG|DSC|DSCN|DSCF|PXL|MVIMG|VID)[_ -]?\d+"#, options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        return name
    }

    static let meaninglessNames: Set<String> = ["image", "file", "document", "untitled", "photo", "attachment"]
}

/// One capture, written by any capture surface into the App Group Inbox and
/// ingested later by the main app (Docs/architecture.md §3.1). Immutable once
/// committed; `envelope.json` is written last and acts as the commit marker.
public struct CaptureEnvelope: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: ULID
    public var capturedAt: Date
    public var device: String
    public var surface: CaptureSurface
    public var sourceApp: String?
    public var url: URL?
    public var title: String?
    /// The selected passage; the ingestor turns it into a `SelectionAnchor`.
    public var selection: TextQuote?
    public var text: String?
    public var pageContext: PageContext?
    public var payloadFiles: [PayloadFile]
    public var userIntent: Intent?
    public var userNote: String?
    public var userGroupID: String?

    public init(
        id: ULID,
        capturedAt: Date = Date(),
        device: String,
        surface: CaptureSurface,
        sourceApp: String? = nil,
        url: URL? = nil,
        title: String? = nil,
        selection: TextQuote? = nil,
        text: String? = nil,
        pageContext: PageContext? = nil,
        payloadFiles: [PayloadFile] = [],
        userIntent: Intent? = nil,
        userNote: String? = nil,
        userGroupID: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.capturedAt = capturedAt
        self.device = device
        self.surface = surface
        self.sourceApp = sourceApp
        self.url = url
        self.title = title
        self.selection = selection
        self.text = text
        self.pageContext = pageContext
        self.payloadFiles = payloadFiles
        self.userIntent = userIntent
        self.userNote = userNote
        self.userGroupID = userGroupID
    }
}
