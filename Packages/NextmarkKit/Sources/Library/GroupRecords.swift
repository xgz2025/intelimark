import Foundation
import GRDB
import Model

/// A group of items (PRD G1–G6). `userTitle` always wins over the AI's name.
public struct GroupRecord: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "itemGroup"

    public var id: String
    public var kind: GroupKind
    public var state: GroupState
    public var userTitle: String?
    public var aiTitle: String?
    public var emoji: String?
    public var color: String?
    /// Plans (PRD G6): what the group is for, and by when.
    public var goal: String?
    public var targetDate: Date?
    public var brief: GroupBrief?
    public var briefVersion: Int
    /// The member set and their derived versions the brief was written from.
    public var briefInputsHash: String?
    public var briefUpdatedAt: Date?
    public var status: GroupStatus
    public var outcome: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = ULID().rawValue,
        kind: GroupKind,
        state: GroupState,
        userTitle: String? = nil,
        aiTitle: String? = nil,
        emoji: String? = nil,
        now: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.userTitle = userTitle
        self.aiTitle = aiTitle
        self.emoji = emoji
        color = nil
        goal = nil
        targetDate = nil
        brief = nil
        briefVersion = 0
        briefInputsHash = nil
        briefUpdatedAt = nil
        status = .active
        outcome = nil
        createdAt = now
        updatedAt = now
    }

    public var displayTitle: String {
        for candidate in [userTitle, aiTitle, brief?.title] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return String(localized: "Untitled Group")
    }

    public var isPlan: Bool { kind == .plan }
}

/// An item in a group. A membership the user made or confirmed is `locked`: the AI
/// never removes it. One the user removed stays as `excluded`, so it isn't suggested again.
public struct MembershipRecord: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "membership"

    public var groupID: String
    public var itemID: String
    public var origin: MembershipOrigin
    public var score: Double?
    public var locked: Bool
    public var excluded: Bool
    public var addedAt: Date

    public init(groupID: String, itemID: String, origin: MembershipOrigin, score: Double? = nil, locked: Bool, now: Date = Date()) {
        self.groupID = groupID
        self.itemID = itemID
        self.origin = origin
        self.score = score
        self.locked = locked
        excluded = false
        addedAt = now
    }

    /// Proposed by the AI and not yet confirmed.
    public var isSuggested: Bool { !locked && !excluded }
}

/// A to-do on an item or a group (PRD A1).
public struct ActionRecord: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "action"

    public var id: String
    public var itemID: String?
    public var groupID: String?
    public var title: String
    public var dueAt: Date?
    public var status: ActionStatus
    public var origin: ActionOrigin
    public var reminderID: String?
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: String = ULID().rawValue,
        title: String,
        dueAt: Date? = nil,
        itemID: String? = nil,
        groupID: String? = nil,
        status: ActionStatus = .open,
        origin: ActionOrigin = .user,
        now: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.groupID = groupID
        self.title = title
        self.dueAt = dueAt
        self.status = status
        self.origin = origin
        reminderID = nil
        createdAt = now
        completedAt = nil
    }
}

extension ItemRecord {
    /// The item as briefs and action suggestions see it.
    public var digest: ItemDigest {
        ItemDigest(
            id: id,
            title: displayTitle,
            summary: summary,
            kind: semanticKind,
            intent: intent ?? suggestedIntent,
            note: note,
            facts: typedFields?.digestFacts ?? [],
            keywords: keywords,
            dates: dates,
            places: places
        )
    }
}

extension TypedFields {
    /// A few short facts for prompts and comparisons.
    var digestFacts: [String] {
        var facts: [String] = []
        if let product {
            if let price = product.price {
                facts.append("Price: \(price.formatted()) \(product.currency ?? "")".trimmingCharacters(in: .whitespaces))
            }
            if let brand = product.brand { facts.append("Brand: \(brand)") }
        }
        if let place {
            if let address = place.address { facts.append("Address: \(address)") }
        }
        if let event {
            if let venue = event.venue { facts.append("Venue: \(venue)") }
        }
        if let recipe {
            if let minutes = recipe.totalMinutes { facts.append("Time: \(minutes) min") }
            if !recipe.ingredients.isEmpty { facts.append("Ingredients: \(recipe.ingredients.prefix(6).joined(separator: ", "))") }
        }
        if let article, let author = article.author {
            facts.append("By \(author)")
        }
        return facts
    }
}
