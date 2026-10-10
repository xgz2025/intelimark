import Foundation
import GRDB
import Model
import Capture
import UniformTypeIdentifiers

/// A saved item. Columns are grouped into three layers with the precedence
/// `user > derived > source` (Docs/architecture.md §4).
public struct ItemRecord: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item"

    public var id: String
    public var kind: ItemKind
    public var status: ItemStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var surface: CaptureSurface
    public var sourceApp: String?
    public var capturedOn: String
    public var canonicalURL: String?
    public var contentHash: String?

    // Source facts
    public var sourceTitle: String?
    public var text: String?
    public var anchor: SelectionAnchor?
    public var pageContext: PageContext?

    // Derived
    public var aiTitle: String?
    public var summary: String?
    public var imageDescription: String?
    public var ocrText: String?
    public var contentText: String?
    public var siteName: String?
    public var heroImageURL: String?
    public var imageLabels: [String]
    public var barcodes: [String]
    public var structuredKind: SemanticKind?
    public var typedFields: TypedFields?
    public var extractVersion: Int
    public var semanticKind: SemanticKind?
    public var suggestedIntent: Intent?
    public var keywords: [String]
    public var dates: [ItemDate]
    public var places: [ItemPlace]
    public var derivedVersion: Int

    // User layer
    public var userTitle: String?
    public var note: String?
    public var intent: Intent?
    public var pinned: Bool
    public var lastOpenedAt: Date?
    public var syncScope: SyncScope

    public var displayTitle: String {
        for candidate in [userTitle, aiTitle, sourceTitle] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        if let canonicalURL { return canonicalURL }
        if let text, !text.isEmpty { return String(text.prefix(120)) }
        if let imageDescription, !imageDescription.isEmpty { return String(imageDescription.prefix(120)) }
        return kind.placeholderTitle
    }

    public var subtitle: String? {
        if let siteName { return siteName }
        if let host = canonicalURL.flatMap({ URL(string: $0) })?.host() { return host }
        return summary
    }
}

extension ItemRecord {
    /// A new inbox item from a committed capture. The item ID is the envelope ID,
    /// which makes ingestion idempotent.
    public init(envelope: CaptureEnvelope, now: Date = Date()) {
        id = envelope.id.rawValue
        kind = ItemKind.inferred(from: envelope)
        status = .inbox
        createdAt = envelope.capturedAt
        updatedAt = now
        surface = envelope.surface
        sourceApp = envelope.sourceApp
        capturedOn = envelope.device
        canonicalURL = (envelope.pageContext?.canonicalURL ?? envelope.url)?.absoluteString
        contentHash = nil

        // A file shared on its own (no page, no link) is titled by its file name.
        sourceTitle = envelope.title
            ?? (envelope.url == nil ? envelope.payloadFiles.lazy.compactMap(\.displayName).first : nil)
        text = envelope.selection?.exact ?? envelope.text
        pageContext = envelope.pageContext
        if let quote = envelope.selection, let url = envelope.url {
            anchor = .web(textFragmentURL: TextFragment.url(for: url, quote: quote) ?? url, quote: quote)
        } else if let url = envelope.url, url.scheme == "message" {
            anchor = .mail(messageURL: url)
        } else {
            anchor = nil
        }

        aiTitle = nil
        summary = nil
        imageDescription = nil
        ocrText = nil
        contentText = nil
        siteName = nil
        heroImageURL = nil
        imageLabels = []
        barcodes = []
        structuredKind = nil
        typedFields = nil
        extractVersion = 0
        semanticKind = nil
        suggestedIntent = nil
        keywords = []
        dates = []
        places = []
        derivedVersion = 0

        userTitle = nil
        note = envelope.userNote
        intent = envelope.userIntent
        pinned = false
        lastOpenedAt = nil
        syncScope = .cloud
    }
}

extension ItemKind {
    /// What to call an item that has no title at all.
    public var placeholderTitle: String {
        switch self {
        case .image: String(localized: "Photo")
        case .pdf: String(localized: "PDF Document")
        case .file: String(localized: "File")
        case .email: String(localized: "Email")
        case .link, .text, .note, .aiSession: String(localized: "Untitled")
        }
    }

    static func inferred(from envelope: CaptureEnvelope) -> ItemKind {
        if let file = envelope.payloadFiles.first {
            let type = UTType(file.contentType)
            if type?.conforms(to: .image) == true { return .image }
            if type?.conforms(to: .pdf) == true { return .pdf }
            return .file
        }
        if let url = envelope.url {
            return url.scheme == "message" ? .email : .link
        }
        if let text = envelope.text, !text.isEmpty { return .text }
        return .note
    }
}

public enum AttachmentRole: String, Codable, Sendable {
    case original, thumbnail, archive, transcript
}

public enum AttachmentSyncPolicy: String, Codable, Sendable {
    case always, ifEnabled, never
}

public struct AttachmentRecord: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment"

    /// `<itemID>-<index>`: the same on every device, so it can name the iCloud record.
    public var id: String
    public var itemID: String
    public var role: AttachmentRole
    public var fileName: String
    public var contentType: String
    public var byteSize: Int64?
    public var syncPolicy: AttachmentSyncPolicy

    public init(
        itemID: String,
        index: Int,
        role: AttachmentRole,
        fileName: String,
        contentType: String,
        byteSize: Int64?,
        syncPolicy: AttachmentSyncPolicy
    ) {
        id = "\(itemID)-\(index < 10 ? "0" : "")\(index)"
        self.itemID = itemID
        self.role = role
        self.fileName = fileName
        self.contentType = contentType
        self.byteSize = byteSize
        self.syncPolicy = syncPolicy
    }
}

public struct JobRecord: Codable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "job"

    public var id: Int64?
    public var itemID: String
    public var stage: PipelineStage
    public var attempts: Int
    public var notBefore: Date

    public init(itemID: String, stage: PipelineStage, attempts: Int = 0, notBefore: Date = Date()) {
        self.itemID = itemID
        self.stage = stage
        self.attempts = attempts
        self.notBefore = notBefore
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
