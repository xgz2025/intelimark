import Foundation
import CryptoKit
import GRDB
import Model

/// A group with its counts, for lists and the sidebar.
public struct GroupSummary: Sendable, Identifiable, Hashable {
    public var group: GroupRecord
    /// Members the user added or confirmed.
    public var memberCount: Int
    /// Members the AI proposed and the user hasn't confirmed yet.
    public var suggestedCount: Int
    public var openActionCount: Int

    public var id: String { group.id }
}

public struct GroupMember: Sendable, Identifiable, Hashable {
    public var item: ItemRecord
    public var membership: MembershipRecord

    public var id: String { item.id }
}

/// Everything the group screen shows.
public struct GroupDetail: Sendable, Equatable {
    public var group: GroupRecord
    /// Confirmed members first, then suggestions; newest first within each.
    public var members: [GroupMember]
    /// Open actions first; dismissed suggestions are left out.
    public var actions: [ActionRecord]
    /// Lowercased titles of every action on the group or its members, dismissed
    /// ones included: suggestions with these titles aren't offered.
    public var knownActionTitles: Set<String>
}

/// Everything the item screen shows besides the item itself.
public struct ItemContext: Sendable, Equatable {
    public var groups: [GroupRecord]
    public var actions: [ActionRecord]
    /// Lowercased titles of every action on the item, dismissed ones included.
    public var knownActionTitles: Set<String>
}

/// Groups and memberships (Docs/architecture.md §4.2, §7). User edits lock what
/// they touch; AI writes only add suggestions and never undo a user's choice.
public struct GroupRepository: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    // MARK: Reading

    public func group(id: String) async throws -> GroupRecord? {
        try await database.writer.read { db in try GroupRecord.fetchOne(db, key: id) }
    }

    /// Live groups in the given states, done groups last, then by title.
    public func summaries(states: [GroupState] = [.accepted]) -> AsyncThrowingStream<[GroupSummary], any Error> {
        let rawStates = states.map(\.rawValue)
        return database.observe { db in
            let groups = try GroupRecord.filter(rawStates.contains(Column("state"))).fetchAll(db)
            var counts: [String: (confirmed: Int, suggested: Int)] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT membership.groupID, SUM(membership.locked) AS confirmed, SUM(1 - membership.locked) AS suggested
                FROM membership JOIN item ON item.id = membership.itemID
                WHERE membership.excluded = 0 AND item.status <> 'trashed'
                GROUP BY membership.groupID
                """) {
                let groupID: String = row["groupID"]
                let confirmed: Int = row["confirmed"]
                let suggested: Int = row["suggested"]
                counts[groupID] = (confirmed, suggested)
            }
            var openActions: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT groupID, COUNT(*) AS open FROM action
                WHERE status = 'open' AND groupID IS NOT NULL GROUP BY groupID
                """) {
                let groupID: String = row["groupID"]
                let open: Int = row["open"]
                openActions[groupID] = open
            }
            return groups
                .map { group in
                    GroupSummary(
                        group: group,
                        memberCount: counts[group.id]?.confirmed ?? 0,
                        suggestedCount: counts[group.id]?.suggested ?? 0,
                        openActionCount: openActions[group.id] ?? 0
                    )
                }
                .sorted { lhs, rhs in
                    let (l, r) = (lhs.group, rhs.group)
                    if l.status != r.status { return l.status == .active }
                    return l.displayTitle.localizedStandardCompare(r.displayTitle) == .orderedAscending
                }
        }
    }

    /// Live group screen; nil once the group is deleted.
    public func detail(id: String) -> AsyncThrowingStream<GroupDetail?, any Error> {
        database.observe { db in
            guard let group = try GroupRecord.fetchOne(db, key: id) else { return nil }
            let memberships = try MembershipRecord
                .filter(Column("groupID") == id && Column("excluded") == false)
                .fetchAll(db)
            let items = try ItemRecord.fetchAll(db, keys: memberships.map(\.itemID))
                .filter { $0.status != .trashed }
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let members = memberships
                .compactMap { membership in byID[membership.itemID].map { GroupMember(item: $0, membership: membership) } }
                .sorted { lhs, rhs in
                    if lhs.membership.locked != rhs.membership.locked { return lhs.membership.locked }
                    return lhs.item.createdAt > rhs.item.createdAt
                }
            let allActions = try ActionRecord
                .filter(Column("groupID") == id || members.map(\.item.id).contains(Column("itemID")))
                .fetchAll(db)
            let actions = allActions
                .filter { $0.groupID == id && $0.status != .dismissed }
                .sorted(by: ActionRecord.displayOrder)
            let known = Set(allActions.map { $0.title.lowercased() })
            return GroupDetail(group: group, members: members, actions: actions, knownActionTitles: known)
        }
    }

    /// Live groups and actions of one item.
    public func context(forItem id: String) -> AsyncThrowingStream<ItemContext, any Error> {
        database.observe { db in
            let groups = try GroupRecord.fetchAll(db, sql: """
                SELECT itemGroup.* FROM itemGroup
                JOIN membership ON membership.groupID = itemGroup.id
                WHERE membership.itemID = ? AND membership.excluded = 0 AND itemGroup.state = 'accepted'
                ORDER BY itemGroup.updatedAt DESC
                """, arguments: [id])
            let allActions = try ActionRecord.filter(Column("itemID") == id).fetchAll(db)
            let actions = allActions
                .filter { $0.status != .dismissed }
                .sorted(by: ActionRecord.displayOrder)
            let known = Set(allActions.map { $0.title.lowercased() })
            return ItemContext(groups: groups, actions: actions, knownActionTitles: known)
        }
    }

    // MARK: User edits

    /// A new manual group, optionally with items in it. Returns its ID.
    @discardableResult
    public func createGroup(title: String, emoji: String? = nil, itemIDs: [String] = [], now: Date = Date()) async throws -> String {
        let group = GroupRecord(kind: .manual, state: .accepted, userTitle: title, emoji: emoji, now: now)
        try await database.writer.write { db in
            try group.insert(db)
            try Self.addUserMembers(itemIDs, to: group.id, db: db, now: now)
        }
        return group.id
    }

    public func rename(_ id: String, to title: String?, emoji: String? = nil, now: Date = Date()) async throws {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await modify(id, now: now) { group in
            group.userTitle = (trimmed?.isEmpty ?? true) ? nil : trimmed
            if let emoji { group.emoji = emoji.isEmpty ? nil : emoji }
        }
    }

    /// Turns a group into a plan with a goal and a date (PRD G6), or updates them.
    public func makePlan(_ id: String, goal: String?, targetDate: Date?, now: Date = Date()) async throws {
        try await modify(id, now: now) { group in
            group.kind = .plan
            group.goal = goal?.trimmingCharacters(in: .whitespacesAndNewlines)
            group.targetDate = targetDate
        }
    }

    /// Done groups collapse into the archive with an optional outcome (PRD A5).
    public func setStatus(_ status: GroupStatus, forGroup id: String, outcome: String? = nil, now: Date = Date()) async throws {
        try await modify(id, now: now) { group in
            group.status = status
            if let outcome { group.outcome = outcome }
        }
    }

    /// Adds items as confirmed members (drag and drop, "Add to Group"). Unknown IDs
    /// are ignored; an item the user removed earlier comes back. Returns how many were added.
    @discardableResult
    public func addItems(_ itemIDs: [String], to groupID: String, now: Date = Date()) async throws -> Int {
        try await database.writer.write { db in
            guard var group = try GroupRecord.fetchOne(db, key: groupID) else { return 0 }
            let added = try Self.addUserMembers(itemIDs, to: groupID, db: db, now: now)
            if added > 0 {
                group.updatedAt = now
                try group.update(db)
            }
            return added
        }
    }

    /// Takes an item out of a group. It stays recorded as excluded, so the AI
    /// doesn't suggest it again.
    public func removeItem(_ itemID: String, from groupID: String, now: Date = Date()) async throws {
        try await changeMembership(itemID, in: groupID, now: now) { membership in
            membership.excluded = true
            membership.locked = true
        }
    }

    /// Confirms an AI suggestion: from now on the AI never removes it.
    public func confirmItem(_ itemID: String, in groupID: String, now: Date = Date()) async throws {
        try await changeMembership(itemID, in: groupID, now: now) { membership in
            membership.locked = true
        }
    }

    /// Accepts a suggested group (PRD G2): it becomes a smart group with its members confirmed.
    public func acceptSuggestion(_ id: String, title: String? = nil, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var group = try GroupRecord.fetchOne(db, key: id), group.state == .suggested else { return }
            group.state = .accepted
            group.kind = .smart
            if let title, !title.isEmpty { group.userTitle = title }
            group.updatedAt = now
            try group.update(db)
            try db.execute(
                sql: "UPDATE membership SET locked = 1 WHERE groupID = ? AND excluded = 0",
                arguments: [id]
            )
        }
    }

    /// Dismisses a suggested group. Its member set is kept so the same cluster
    /// isn't proposed again.
    public func dismissSuggestion(_ id: String, now: Date = Date()) async throws {
        try await modify(id, now: now) { group in
            guard group.state == .suggested else { return }
            group.state = .dismissed
        }
    }

    /// Moves `sourceID`'s members and actions into `targetID`, then deletes it (PRD G2 merge).
    public func merge(_ sourceID: String, into targetID: String, now: Date = Date()) async throws {
        guard sourceID != targetID else { return }
        try await database.writer.write { db in
            guard var target = try GroupRecord.fetchOne(db, key: targetID),
                  let source = try GroupRecord.fetchOne(db, key: sourceID)
            else { return }
            let members = try MembershipRecord
                .filter(Column("groupID") == sourceID && Column("excluded") == false)
                .fetchAll(db)
            try Self.addUserMembers(members.map(\.itemID), to: targetID, db: db, now: now)
            try db.execute(sql: "UPDATE action SET groupID = ? WHERE groupID = ?", arguments: [targetID, sourceID])
            target.updatedAt = now
            try target.update(db)
            try source.delete(db)
        }
    }

    /// Deletes a group, its memberships and its actions. The items stay.
    public func delete(_ id: String) async throws {
        _ = try await database.writer.write { db in try GroupRecord.deleteOne(db, key: id) }
    }

    /// Writes the brief again on the next pipeline pass, without waiting for the debounce.
    public func requestBrief(_ id: String) async throws {
        try await database.writer.write { db in
            guard var group = try GroupRecord.fetchOne(db, key: id) else { return }
            group.briefInputsHash = nil
            group.updatedAt = .distantPast
            try group.update(db)
        }
    }

    // MARK: AI writes

    /// Suggests an item for a group (online assignment, §7). Never touches an
    /// existing membership, including one the user removed. Returns whether it was added.
    @discardableResult
    public func suggestMembership(itemID: String, groupID: String, score: Double, now: Date = Date()) async throws -> Bool {
        try await database.writer.write { db in
            guard try ItemRecord.exists(db, key: itemID), var group = try GroupRecord.fetchOne(db, key: groupID),
                  try MembershipRecord.fetchOne(db, key: ["groupID": groupID, "itemID": itemID]) == nil
            else { return false }
            try MembershipRecord(groupID: groupID, itemID: itemID, origin: .ai, score: score, locked: false, now: now).insert(db)
            group.updatedAt = now
            try group.update(db)
            return true
        }
    }

    /// A group proposed by clustering (§7), waiting for the user. Returns its ID.
    @discardableResult
    public func addSuggestedGroup(title: String?, itemIDs: [String], score: Double? = nil, now: Date = Date()) async throws -> String {
        let group = GroupRecord(kind: .smart, state: .suggested, aiTitle: title, now: now)
        try await database.writer.write { db in
            try group.insert(db)
            for itemID in itemIDs {
                guard try ItemRecord.exists(db, key: itemID) else { continue }
                try MembershipRecord(groupID: group.id, itemID: itemID, origin: .ai, score: score, locked: false, now: now).insert(db)
            }
        }
        return group.id
    }

    /// Member vectors of accepted, active groups for one embedding model, by group.
    /// Suggestions count too, so a group keeps its shape while the user reviews.
    public func memberVectors(modelID: String) async throws -> [String: [[Float]]] {
        try await database.writer.read { db in
            var vectors: [String: [[Float]]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT membership.groupID, embedding.vector FROM membership
                JOIN itemGroup ON itemGroup.id = membership.groupID
                JOIN item ON item.id = membership.itemID
                JOIN embedding ON embedding.itemID = membership.itemID
                WHERE itemGroup.state = 'accepted' AND itemGroup.status = 'active'
                  AND membership.excluded = 0 AND item.status <> 'trashed' AND embedding.modelID = ?
                """, arguments: [modelID]) {
                let groupID: String = row["groupID"]
                let blob: Data = row["vector"]
                vectors[groupID, default: []].append(VectorBlob.decode(blob))
            }
            return vectors
        }
    }

    /// Vectors of recent items that are in no group (not even a suggested one): the
    /// input for discovering new groups.
    public func ungroupedVectors(modelID: String, since: Date, limit: Int = 400) async throws -> [StoredVector] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT item.id, embedding.vector FROM item
                JOIN embedding ON embedding.itemID = item.id AND embedding.modelID = ?
                WHERE item.status IN ('inbox', 'active') AND item.createdAt >= ?
                  AND NOT EXISTS (
                    SELECT 1 FROM membership JOIN itemGroup ON itemGroup.id = membership.groupID
                    WHERE membership.itemID = item.id AND membership.excluded = 0
                      AND itemGroup.state IN ('accepted', 'suggested')
                  )
                ORDER BY item.createdAt DESC
                LIMIT ?
                """, arguments: [modelID, since, limit])
            .map { row in
                let id: String = row["id"]
                let blob: Data = row["vector"]
                return StoredVector(itemID: id, vector: VectorBlob.decode(blob))
            }
        }
    }

    /// Member sets of dismissed suggestions, so the same cluster isn't proposed again.
    public func dismissedMemberSets() async throws -> [Set<String>] {
        try await database.writer.read { db in
            var sets: [String: Set<String>] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT membership.groupID, membership.itemID FROM membership
                JOIN itemGroup ON itemGroup.id = membership.groupID
                WHERE itemGroup.state = 'dismissed'
                """) {
                let groupID: String = row["groupID"]
                let itemID: String = row["itemID"]
                sets[groupID, default: []].insert(itemID)
            }
            return Array(sets.values)
        }
    }

    // MARK: Briefs

    /// Accepted groups whose members changed since their brief was written, and
    /// that haven't changed for `debounce` (so a burst of edits writes one brief).
    public func groupIDsNeedingBrief(now: Date = Date(), debounce: TimeInterval = 10 * 60) async throws -> [String] {
        try await database.writer.read { db in
            let groups = try GroupRecord
                .filter(Column("state") == GroupState.accepted.rawValue && Column("status") == GroupStatus.active.rawValue)
                .fetchAll(db)
            var ids: [String] = []
            for group in groups where group.updatedAt <= now.addingTimeInterval(-debounce) {
                let members = try Self.briefMembers(of: group.id, db: db)
                guard !members.isEmpty, Self.briefInputsHash(group: group, members: members) != group.briefInputsHash else { continue }
                ids.append(group.id)
            }
            return ids
        }
    }

    /// The group and its confirmed members, newest first, with the hash of these inputs.
    public func briefInputs(for id: String) async throws -> (group: GroupRecord, members: [ItemRecord], hash: String)? {
        try await database.writer.read { db in
            guard let group = try GroupRecord.fetchOne(db, key: id) else { return nil }
            let members = try Self.briefMembers(of: id, db: db)
            return (group, members, Self.briefInputsHash(group: group, members: members))
        }
    }

    /// Stores a brief. A provisional (heuristic) brief is stored as version 0 so it
    /// is written again once the on-device model is available.
    public func saveBrief(_ brief: GroupBrief, inputsHash: String, version: Int, toGroup id: String, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var group = try GroupRecord.fetchOne(db, key: id) else { return }
            group.brief = brief
            group.briefVersion = version
            group.briefInputsHash = inputsHash
            group.briefUpdatedAt = now
            if group.aiTitle == nil || group.kind == .smart { group.aiTitle = brief.title }
            try group.update(db)
        }
    }

    /// Accepted groups whose brief is older than `version` (or provisional).
    public func groupIDsWithStaleBriefs(below version: Int) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM itemGroup
                WHERE state = 'accepted' AND status = 'active' AND brief IS NOT NULL AND briefVersion < ?
                """, arguments: [version])
        }
    }

    /// Marks briefs as outdated so the next pass writes them again.
    public func invalidateBriefs(_ ids: [String]) async throws {
        try await database.writer.write { db in
            for id in ids {
                try db.execute(sql: "UPDATE itemGroup SET briefInputsHash = NULL WHERE id = ?", arguments: [id])
            }
        }
    }

    // MARK: Helpers

    static func briefMembers(of groupID: String, db: Database) throws -> [ItemRecord] {
        try ItemRecord.fetchAll(db, sql: """
            SELECT item.* FROM item JOIN membership ON membership.itemID = item.id
            WHERE membership.groupID = ? AND membership.locked = 1 AND membership.excluded = 0
              AND item.status <> 'trashed'
            ORDER BY item.createdAt DESC
            """, arguments: [groupID])
    }

    /// Changes when the members, their understanding, or the group's title and goal change.
    static func briefInputsHash(group: GroupRecord, members: [ItemRecord]) -> String {
        let memberPart = members
            .map { "\($0.id):\($0.derivedVersion):\($0.note ?? "")" }
            .sorted()
            .joined(separator: "|")
        let input = [group.userTitle ?? "", group.goal ?? "", memberPart].joined(separator: "\n")
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func addUserMembers(_ itemIDs: [String], to groupID: String, db: Database, now: Date) throws -> Int {
        var added = 0
        for itemID in Set(itemIDs) {
            guard try ItemRecord.exists(db, key: itemID) else { continue }
            if var existing = try MembershipRecord.fetchOne(db, key: ["groupID": groupID, "itemID": itemID]) {
                guard existing.excluded || !existing.locked else { continue }
                existing.excluded = false
                existing.locked = true
                try existing.update(db)
            } else {
                try MembershipRecord(groupID: groupID, itemID: itemID, origin: .user, locked: true, now: now).insert(db)
            }
            added += 1
        }
        return added
    }

    private func modify(_ id: String, now: Date, _ change: @escaping @Sendable (inout GroupRecord) -> Void) async throws {
        try await database.writer.write { db in
            guard var group = try GroupRecord.fetchOne(db, key: id) else { return }
            change(&group)
            group.updatedAt = now
            try group.update(db)
        }
    }

    private func changeMembership(
        _ itemID: String, in groupID: String, now: Date,
        _ change: @escaping @Sendable (inout MembershipRecord) -> Void
    ) async throws {
        try await database.writer.write { db in
            guard var membership = try MembershipRecord.fetchOne(db, key: ["groupID": groupID, "itemID": itemID]),
                  var group = try GroupRecord.fetchOne(db, key: groupID)
            else { return }
            change(&membership)
            try membership.update(db)
            group.updatedAt = now
            try group.update(db)
        }
    }
}

extension ActionRecord {
    /// Open before done; earliest due first, undated after dated; then oldest first.
    public static func displayOrder(_ lhs: ActionRecord, _ rhs: ActionRecord) -> Bool {
        if lhs.status != rhs.status { return lhs.status == .open }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (l?, r?) where l != r: return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.createdAt < rhs.createdAt
        }
    }
}
