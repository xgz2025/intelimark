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
import GRDB
import Model

/// An open action with what it belongs to, for the Next Actions list (PRD A4).
public struct ActionContext: Sendable, Identifiable, Hashable {
    public var action: ActionRecord
    public var itemTitle: String?
    public var groupTitle: String?
    public var groupEmoji: String?

    public var id: String { action.id }
}

/// What completing an action finished: when it was the last open action of its
/// item or group, the UI offers to mark that done too (PRD A5).
public struct ActionCompletion: Sendable, Equatable {
    public var finishedItemID: String?
    public var finishedGroupID: String?

    public init(finishedItemID: String? = nil, finishedGroupID: String? = nil) {
        self.finishedItemID = finishedItemID
        self.finishedGroupID = finishedGroupID
    }
}

/// Actions on items and groups (PRD A1, A2, A5).
public struct ActionRepository: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    @discardableResult
    public func add(
        title: String,
        dueAt: Date? = nil,
        itemID: String? = nil,
        groupID: String? = nil,
        origin: ActionOrigin = .user,
        now: Date = Date()
    ) async throws -> String {
        let action = ActionRecord(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueAt: dueAt, itemID: itemID, groupID: groupID, origin: origin, now: now
        )
        try await database.writer.write { db in try action.insert(db) }
        return action.id
    }

    /// Confirms a suggestion with one tap (PRD A2).
    @discardableResult
    public func accept(_ suggestion: SuggestedAction, groupID: String? = nil, now: Date = Date()) async throws -> String {
        try await add(
            title: suggestion.title, dueAt: suggestion.dueAt,
            itemID: suggestion.itemID, groupID: groupID, origin: .aiAccepted, now: now
        )
    }

    /// Turns a suggestion down; it is remembered so it isn't suggested again.
    public func dismiss(_ suggestion: SuggestedAction, groupID: String? = nil, now: Date = Date()) async throws {
        let action = ActionRecord(
            title: suggestion.title, dueAt: suggestion.dueAt, itemID: suggestion.itemID,
            groupID: groupID, status: .dismissed, origin: .aiSuggested, now: now
        )
        try await database.writer.write { db in try action.insert(db) }
    }

    /// Titles (lowercased) of every action on these items or this group, whatever
    /// their status: suggestions with these titles are not offered again.
    public func knownTitles(itemIDs: [String] = [], groupID: String? = nil) async throws -> Set<String> {
        try await database.writer.read { db in
            var request = ActionRecord.filter(itemIDs.contains(Column("itemID")))
            if let groupID {
                request = ActionRecord.filter(itemIDs.contains(Column("itemID")) || Column("groupID") == groupID)
            }
            return Set(try request.fetchAll(db).map { $0.title.lowercased() })
        }
    }

    /// Checks an action off (or back on). Returns what that finished, if anything.
    @discardableResult
    public func setDone(_ done: Bool, forAction id: String, now: Date = Date()) async throws -> ActionCompletion {
        try await database.writer.write { db in
            guard var action = try ActionRecord.fetchOne(db, key: id) else { return ActionCompletion() }
            action.status = done ? .done : .open
            action.completedAt = done ? now : nil
            try action.update(db)
            guard done else { return ActionCompletion() }
            var completion = ActionCompletion()
            if let itemID = action.itemID, try Self.openCount(db, column: "itemID", id: itemID) == 0,
               let item = try ItemRecord.fetchOne(db, key: itemID), item.status != .done {
                completion.finishedItemID = itemID
            }
            if let groupID = action.groupID, try Self.openCount(db, column: "groupID", id: groupID) == 0,
               let group = try GroupRecord.fetchOne(db, key: groupID), group.status != .done {
                completion.finishedGroupID = groupID
            }
            return completion
        }
    }

    public func update(_ id: String, title: String, dueAt: Date?) async throws {
        try await database.writer.write { db in
            guard var action = try ActionRecord.fetchOne(db, key: id) else { return }
            action.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            action.dueAt = dueAt
            try action.update(db)
        }
    }

    public func delete(_ id: String) async throws {
        _ = try await database.writer.write { db in try ActionRecord.deleteOne(db, key: id) }
    }

    /// Live open actions across the library, earliest due first, with their item or group.
    public func nextActions() -> AsyncThrowingStream<[ActionContext], any Error> {
        database.observe { db in try Self.fetchOpenActions(db) }
    }

    /// Open actions with their item or group, earliest due first (for Moments).
    public func openActions() async throws -> [ActionContext] {
        try await database.writer.read { db in try Self.fetchOpenActions(db) }
    }

    static func fetchOpenActions(_ db: Database) throws -> [ActionContext] {
        let actions = try ActionRecord
            .filter(Column("status") == ActionStatus.open.rawValue)
            .fetchAll(db)
            .sorted(by: ActionRecord.displayOrder)
        let items = try ItemRecord.fetchAll(db, keys: Array(Set(actions.compactMap(\.itemID))))
        let groups = try GroupRecord.fetchAll(db, keys: Array(Set(actions.compactMap(\.groupID))))
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groupsByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return actions.compactMap { action in
            let item = action.itemID.flatMap { itemsByID[$0] }
            let group = action.groupID.flatMap { groupsByID[$0] }
            // Actions of trashed items and done groups drop out of the list.
            if item?.status == .trashed || group?.status == .done { return nil }
            return ActionContext(
                action: action, itemTitle: item?.displayTitle,
                groupTitle: group?.displayTitle, groupEmoji: group?.emoji
            )
        }
    }

    static func openCount(_ db: Database, column: String, id: String) throws -> Int {
        try ActionRecord
            .filter(Column(column) == id && Column("status") == ActionStatus.open.rawValue)
            .fetchCount(db)
    }
}
