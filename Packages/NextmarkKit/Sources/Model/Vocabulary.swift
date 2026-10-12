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

/// Why the user saved something (Docs/prd.md §2). First-class data, not a tag.
public enum Intent: String, Codable, Sendable, CaseIterable, Identifiable {
    case read
    case buy
    case tryIt = "try"
    case go
    case decide
    case reference
    case forSomeone = "for_someone"

    public var id: String { rawValue }
}

/// What was captured, structurally.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case link, image, text, pdf, file, email, note
    /// Reserved for the 1.1 "Work" update (Docs/ai_sessions_spec.md §7).
    case aiSession
}

/// What the content is about, as guessed by enrichment. Drives typed fields and Compare.
public enum SemanticKind: String, Codable, Sendable, CaseIterable {
    case article, product, place, event, recipe, video, person, receipt, ticket, quote, document, other
}

public enum ItemStatus: String, Codable, Sendable, CaseIterable {
    case inbox, active, done, faded, trashed
    /// Auto-captured material: searchable and reportable, never in the Inbox.
    case log
}

/// Whether an item may leave this device through iCloud sync.
public enum SyncScope: String, Codable, Sendable {
    case cloud, local
}

public enum CaptureSurface: String, Codable, Sendable {
    case shareSheet, safariExtension, services, quickCapture, appIntent, inApp, screenshotImport
}

/// Enrichment stages, in pipeline order (Docs/architecture.md §5).
public enum PipelineStage: Int, Codable, Sendable, CaseIterable {
    case extract, prefilter, understand, digest, embed, index, group, moments, rollup
}

/// The result of the Understand stage, whichever understander produced it.
public struct Understanding: Sendable, Equatable {
    public var title: String
    public var summary: String
    public var semanticKind: SemanticKind
    public var likelyIntent: Intent?
    public var keywords: [String]
    /// What a photo or screenshot shows, so it is findable by text (PRD U3). Nil for other items.
    public var imageDescription: String?
    /// Grounded dates and places (PRD U2); structured facts are merged in later.
    public var dates: [ItemDate]
    public var places: [ItemPlace]
    /// Which understander produced this, e.g. "foundation-models" or "heuristic".
    public var producer: String
    /// True for the no-model fallback: the item is understood again once the
    /// on-device model is available.
    public var isProvisional: Bool

    public init(
        title: String,
        summary: String,
        semanticKind: SemanticKind,
        likelyIntent: Intent?,
        keywords: [String],
        imageDescription: String? = nil,
        dates: [ItemDate] = [],
        places: [ItemPlace] = [],
        producer: String,
        isProvisional: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.semanticKind = semanticKind
        self.likelyIntent = likelyIntent
        self.keywords = keywords
        self.imageDescription = imageDescription
        self.dates = dates
        self.places = places
        self.producer = producer
        self.isProvisional = isProvisional
    }
}
