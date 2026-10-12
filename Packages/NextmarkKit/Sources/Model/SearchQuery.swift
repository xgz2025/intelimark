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

/// What the user is looking for: free text plus structured filters (PRD F1, F2).
/// Built by the search UI, or by a `QueryInterpreter` from natural language
/// ("pdfs about tax from last week"). Empty filter sets mean "any". Filters combine
/// with AND, except `kinds` and `captureKinds`, which form one facet: an item matches
/// if either its content kind or its capture kind is listed ("photos or products").
public struct SearchQuery: Sendable, Equatable {
    public var text: String
    /// What the content is about (product, place, event…).
    public var kinds: Set<SemanticKind>
    /// What was captured (photo, PDF, link…).
    public var captureKinds: Set<ItemKind>
    /// The user's intent, or the suggested one when the user didn't pick one.
    public var intents: Set<Intent>
    /// Empty means every status except trashed.
    public var statuses: Set<ItemStatus>
    /// When the item was saved.
    public var savedWithin: DateInterval?
    /// A host or site name, e.g. "nytimes.com" or "Herman Miller". Case-insensitive.
    public var site: String?

    public init(
        text: String = "",
        kinds: Set<SemanticKind> = [],
        captureKinds: Set<ItemKind> = [],
        intents: Set<Intent> = [],
        statuses: Set<ItemStatus> = [],
        savedWithin: DateInterval? = nil,
        site: String? = nil
    ) {
        self.text = text
        self.kinds = kinds
        self.captureKinds = captureKinds
        self.intents = intents
        self.statuses = statuses
        self.savedWithin = savedWithin
        self.site = site
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasFilters: Bool {
        !kinds.isEmpty || !captureKinds.isEmpty || !intents.isEmpty || !statuses.isEmpty
            || savedWithin != nil || !(site ?? "").isEmpty
    }
}
