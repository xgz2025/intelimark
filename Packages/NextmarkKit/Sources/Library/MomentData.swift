import Foundation
import GRDB
import Model

/// How the user answered a notification (PRD M5).
public enum NotificationOutcome: String, Codable, Sendable {
    case opened, done, snoozed, dismissed
}

public struct LedgerEntry: Codable, Sendable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "notificationLedger"

    public var id: Int64?
    public var reason: String
    public var targetID: String
    public var outcome: NotificationOutcome
    public var recordedAt: Date

    public init(reason: String, targetID: String, outcome: NotificationOutcome, recordedAt: Date) {
        self.reason = reason
        self.targetID = targetID
        self.outcome = outcome
        self.recordedAt = recordedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Local record of notification outcomes; never synced (Docs/architecture.md §4.2).
public struct NotificationLedger: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func record(reason: String, targetID: String, outcome: NotificationOutcome, now: Date = Date()) async throws {
        try await database.writer.write { db in
            var entry = LedgerEntry(reason: reason, targetID: targetID, outcome: outcome, recordedAt: now)
            try entry.insert(db)
        }
    }

    /// Entries since `date`, newest first.
    public func entries(since date: Date) async throws -> [LedgerEntry] {
        try await database.writer.read { db in
            try LedgerEntry
                .filter(Column("recordedAt") >= date)
                .order(Column("recordedAt").desc, Column("id").desc)
                .fetchAll(db)
        }
    }
}

/// Why an item is in the Weekly Review (PRD M2).
public enum ReviewReason: Sendable, Hashable {
    /// Saved in the last week and still in the Inbox.
    case new
    /// A date of its own is coming up.
    case comingUp(Date)
    /// Has open actions.
    case hasActions(Int)
    /// Untouched for a long time, with nothing to do.
    case stale
}

public struct ReviewCard: Sendable, Identifiable, Hashable {
    public var item: ItemRecord
    public var reason: ReviewReason

    public var id: String { item.id }
}

extension ItemRepository {
    /// Items in play that have dates, for time Moments (PRD M1).
    public func itemsWithDates() async throws -> [ItemRecord] {
        try await database.writer.read { db in
            try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .filter(Column("dates") != "[]")
                .fetchAll(db)
        }
    }

    /// Records that the user looked at an item; stale detection uses it.
    public func markOpened(_ id: String, now: Date = Date()) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE item SET lastOpenedAt = ? WHERE id = ?", arguments: [now, id])
        }
    }

    /// The Weekly Review stack (PRD M2): what's coming up or has open actions,
    /// then this week's new saves, then things untouched for 30 days. Each item once.
    public func reviewQueue(now: Date = Date(), limit: Int = 15) async throws -> [ReviewCard] {
        try await database.writer.read { db in
            let inPlay = [ItemStatus.inbox.rawValue, ItemStatus.active.rawValue]
            let items = try ItemRecord.filter(inPlay.contains(Column("status"))).order(Column("createdAt").desc).fetchAll(db)
            var openActions: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT itemID, COUNT(*) AS open FROM action WHERE status = 'open' AND itemID IS NOT NULL GROUP BY itemID
                """) {
                let itemID: String = row["itemID"]
                let open: Int = row["open"]
                openActions[itemID] = open
            }
            return Self.reviewCards(items: items, openActions: openActions, now: now, limit: limit)
        }
    }

    static func reviewCards(items: [ItemRecord], openActions: [String: Int], now: Date, limit: Int) -> [ReviewCard] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let staleBefore = now.addingTimeInterval(-30 * 86_400)
        let soon = now.addingTimeInterval(14 * 86_400)
        var cards: [ReviewCard] = []
        var seen = Set<String>()
        func add(_ item: ItemRecord, _ reason: ReviewReason) {
            guard cards.count < limit, seen.insert(item.id).inserted else { return }
            cards.append(ReviewCard(item: item, reason: reason))
        }
        for item in items {
            if let next = item.dates.map(\.date).filter({ $0 > now && $0 <= soon }).min() {
                add(item, .comingUp(next))
            } else if let open = openActions[item.id], open > 0 {
                add(item, .hasActions(open))
            }
        }
        for item in items where item.status == .inbox && item.createdAt >= weekAgo {
            add(item, .new)
        }
        for item in items.reversed() where (item.lastOpenedAt ?? item.createdAt) < staleBefore && openActions[item.id] == nil {
            add(item, .stale)
        }
        return cards
    }
}
