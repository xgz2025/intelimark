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

/// How a group came to be (Docs/architecture.md §4.2).
public enum GroupKind: String, Codable, Sendable, CaseIterable {
    /// Made by the user.
    case manual
    /// Proposed by clustering and accepted by the user.
    case smart
    /// A group with a goal and a date (PRD G6).
    case plan
    /// Reserved for AI-session workstreams (Docs/ai_sessions_spec.md).
    case workstream
}

/// Smart groups start as suggestions; only accepted groups are shown as groups.
public enum GroupState: String, Codable, Sendable {
    case suggested, accepted, dismissed
}

public enum GroupStatus: String, Codable, Sendable {
    case active, done
}

public enum MembershipOrigin: String, Codable, Sendable {
    case user, ai
}

public enum ActionStatus: String, Codable, Sendable {
    case open, done
    /// A suggestion the user turned down; kept so it isn't suggested again.
    case dismissed
}

public enum ActionOrigin: String, Codable, Sendable {
    case user
    /// Suggested and not yet confirmed (only stored when dismissed).
    case aiSuggested
    /// Suggested and confirmed with one tap (PRD A2).
    case aiAccepted
}

/// An action the app proposes; it becomes an `Action` when the user confirms it.
public struct SuggestedAction: Codable, Sendable, Hashable {
    public var title: String
    public var dueAt: Date?
    /// The item it is about, when it comes from one item.
    public var itemID: String?

    public init(title: String, dueAt: Date? = nil, itemID: String? = nil) {
        self.title = title
        self.dueAt = dueAt
        self.itemID = itemID
    }
}

/// A group's overview (PRD G3), written by the on-device model or, without it,
/// by a heuristic (`isProvisional`) and rewritten once the model is available.
public struct GroupBrief: Codable, Sendable, Hashable {
    public var title: String
    public var overview: String
    public var keyPoints: [String]
    public var openQuestions: [String]
    public var suggestedActions: [SuggestedAction]
    public var producer: String
    public var isProvisional: Bool

    public init(
        title: String,
        overview: String,
        keyPoints: [String] = [],
        openQuestions: [String] = [],
        suggestedActions: [SuggestedAction] = [],
        producer: String,
        isProvisional: Bool = false
    ) {
        self.title = title
        self.overview = overview
        self.keyPoints = keyPoints
        self.openQuestions = openQuestions
        self.suggestedActions = suggestedActions
        self.producer = producer
        self.isProvisional = isProvisional
    }
}

/// A compact view of an item for briefs and action suggestions: about 60 tokens.
public struct ItemDigest: Sendable, Equatable {
    public var id: String
    public var title: String
    public var summary: String?
    public var kind: SemanticKind?
    public var intent: Intent?
    public var note: String?
    /// Short facts from typed fields, e.g. "Price: 1395 USD".
    public var facts: [String]
    public var keywords: [String]
    public var dates: [ItemDate]
    public var places: [ItemPlace]

    public init(
        id: String,
        title: String,
        summary: String? = nil,
        kind: SemanticKind? = nil,
        intent: Intent? = nil,
        note: String? = nil,
        facts: [String] = [],
        keywords: [String] = [],
        dates: [ItemDate] = [],
        places: [ItemPlace] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.intent = intent
        self.note = note
        self.facts = facts
        self.keywords = keywords
        self.dates = dates
        self.places = places
    }
}
