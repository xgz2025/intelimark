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
import Testing
import GRDB
import Model
@testable import Library

/// The first value of a live query.
func firstValue<Value: Sendable>(_ stream: AsyncThrowingStream<Value, any Error>) async throws -> Value? {
    for try await value in stream { return value }
    return nil
}

struct LibraryFixture {
    let database: LibraryDatabase
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    var items: ItemRepository { ItemRepository(database: database) }
    var groups: GroupRepository { GroupRepository(database: database) }
    var actions: ActionRepository { ActionRepository(database: database) }

    init() throws {
        database = try LibraryDatabase.inMemory()
    }

    @discardableResult
    func insertItem(_ title: String, daysAgo: Double = 0, _ configure: (inout ItemRecord) -> Void = { _ in }) async throws -> String {
        var item = ItemRecord(envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, title: title), now: now)
        item.createdAt = now.addingTimeInterval(-daysAgo * 86_400)
        configure(&item)
        let record = item
        try await database.writer.write { db in try record.insert(db) }
        return record.id
    }
}

struct GroupRepositoryTests {
    let fixture: LibraryFixture
    var groups: GroupRepository { fixture.groups }
    var now: Date { fixture.now }

    init() throws {
        fixture = try LibraryFixture()
    }

    func insertThree() async throws -> [String] {
        var ids: [String] = []
        for title in ["A", "B", "C"] {
            ids.append(try await fixture.insertItem(title))
        }
        return ids
    }

    func summary(_ id: String, states: [GroupState] = [.accepted, .suggested]) async throws -> GroupSummary? {
        try await firstValue(groups.summaries(states: states))?.first { $0.id == id }
    }

    @Test func manualGroupsHoldTheItemsAddedToThem() async throws {
        let a = try await fixture.insertItem("Ichiran")
        let b = try await fixture.insertItem("Kinkaku-ji")
        let id = try await groups.createGroup(title: "Kyoto", emoji: "🧳", itemIDs: [a, "unknown"], now: now)
        #expect(try await groups.addItems([b, a, "unknown"], to: id, now: now) == 1)

        let summary = try #require(try await summary(id))
        #expect(summary.group.displayTitle == "Kyoto")
        #expect(summary.group.kind == .manual)
        #expect(summary.memberCount == 2)
        #expect(summary.suggestedCount == 0)

        let detail = try #require(try await firstValue(groups.detail(id: id)) ?? nil)
        #expect(Set(detail.members.map(\.item.id)) == [a, b])
        #expect(detail.members.allSatisfy { $0.membership.locked && $0.membership.origin == .user })
    }

    @Test func removedItemsAreNeverSuggestedAgain() async throws {
        let item = try await fixture.insertItem("Ramen")
        let id = try await groups.createGroup(title: "Food", itemIDs: [item], now: now)
        try await groups.removeItem(item, from: id, now: now)
        #expect(try await summary(id)?.memberCount == 0)
        let suggestedAgain = try await groups.suggestMembership(itemID: item, groupID: id, score: 0.9, now: now)
        #expect(!suggestedAgain)

        // The user can still add it back.
        #expect(try await groups.addItems([item], to: id, now: now) == 1)
        #expect(try await summary(id)?.memberCount == 1)
    }

    @Test func suggestionsWaitForConfirmation() async throws {
        let first = try await fixture.insertItem("Desk")
        let second = try await fixture.insertItem("Chair")
        let id = try await groups.createGroup(title: "Office", itemIDs: [first], now: now)
        #expect(try await groups.suggestMembership(itemID: second, groupID: id, score: 0.8, now: now))
        let suggestedTwice = try await groups.suggestMembership(itemID: second, groupID: id, score: 0.9, now: now)
        #expect(!suggestedTwice)
        #expect(try await summary(id)?.suggestedCount == 1)

        try await groups.confirmItem(second, in: id, now: now)
        let confirmed = try #require(try await summary(id))
        #expect(confirmed.memberCount == 2)
        #expect(confirmed.suggestedCount == 0)
    }

    @Test func acceptingASuggestedGroupConfirmsItsMembers() async throws {
        let items = try await insertThree()
        let id = try await groups.addSuggestedGroup(title: "Kyoto", itemIDs: items + ["unknown"], score: 0.7, now: now)
        let suggested = try #require(try await summary(id, states: [.suggested]))
        #expect(suggested.suggestedCount == 3)
        #expect(try await summary(id, states: [.accepted]) == nil)

        try await groups.acceptSuggestion(id, now: now)
        let accepted = try #require(try await summary(id, states: [.accepted]))
        #expect(accepted.group.kind == .smart)
        #expect(accepted.memberCount == 3)
    }

    @Test func freeKeepsThreeSmartGroups() async throws {
        let items = try await insertThree()
        // Each suggestion is named by its members, so they need different ones.
        let memberSets = [[items[0]], [items[1]], [items[2]], [items[0], items[1]], [items[1], items[2]]]
        var ids: [String] = []
        for (title, members) in zip(["Kyoto", "Desk", "Ramen", "Garden"], memberSets) {
            ids.append(try await groups.addSuggestedGroup(title: title, itemIDs: members, score: 0.7, now: now))
        }
        for id in ids.prefix(3) {
            try await groups.acceptSuggestion(id, smartGroupLimit: 3, now: now)
        }
        await #expect(throws: GroupLimitReached(limit: 3)) {
            try await groups.acceptSuggestion(ids[3], smartGroupLimit: 3, now: now)
        }
        #expect(try await summary(ids[3], states: [.suggested]) != nil)

        // A finished group frees its place; Pro has no limit at all.
        try await groups.setStatus(.done, forGroup: ids[0], now: now)
        try await groups.acceptSuggestion(ids[3], smartGroupLimit: 3, now: now)
        let more = try await groups.addSuggestedGroup(title: "Books", itemIDs: memberSets[4], score: 0.7, now: now)
        try await groups.acceptSuggestion(more, smartGroupLimit: nil, now: now)
        #expect(try await summary(more, states: [.accepted]) != nil)
    }

    @Test func dismissedSuggestionsAreRemembered() async throws {
        let items = try await insertThree()
        let id = try await groups.addSuggestedGroup(title: nil, itemIDs: items, now: now)
        try await groups.dismissSuggestion(id, now: now)
        #expect(try await groups.dismissedMemberSets() == [Set(items)])
        #expect(try await summary(id) == nil)
    }

    @Test func mergingMovesMembersAndActions() async throws {
        let a = try await fixture.insertItem("A")
        let b = try await fixture.insertItem("B")
        let target = try await groups.createGroup(title: "Trip", itemIDs: [a], now: now)
        let source = try await groups.createGroup(title: "Hotels", itemIDs: [a, b], now: now)
        try await fixture.actions.add(title: "Book a hotel", groupID: source, now: now)

        try await groups.merge(source, into: target, now: now)
        #expect(try await groups.group(id: source) == nil)
        let detail = try #require(try await firstValue(groups.detail(id: target)) ?? nil)
        #expect(Set(detail.members.map(\.item.id)) == [a, b])
        #expect(detail.actions.map(\.title) == ["Book a hotel"])
    }

    @Test func deletingAGroupKeepsItsItems() async throws {
        let item = try await fixture.insertItem("A")
        let id = try await groups.createGroup(title: "Temp", itemIDs: [item], now: now)
        try await fixture.actions.add(title: "Do it", groupID: id, now: now)
        try await groups.delete(id)
        #expect(try await fixture.items.item(id: item) != nil)
        #expect(try await firstValue(fixture.actions.nextActions())?.isEmpty == true)
    }

    @Test func plansHaveAGoalAndADate() async throws {
        let id = try await groups.createGroup(title: "Kyoto", now: now)
        let date = now.addingTimeInterval(30 * 86_400)
        try await groups.makePlan(id, goal: " Autumn trip ", targetDate: date, now: now)
        let group = try #require(try await groups.group(id: id))
        #expect(group.kind == .plan)
        #expect(group.goal == "Autumn trip")
        #expect(group.targetDate == date)

        try await groups.setStatus(.done, forGroup: id, outcome: "Booked everything", now: now)
        #expect(try await groups.group(id: id)?.status == .done)
        #expect(try await groups.group(id: id)?.outcome == "Booked everything")
    }

    @Test func briefsAreWrittenAfterMembersSettle() async throws {
        let item = try await fixture.insertItem("A")
        let id = try await groups.createGroup(title: "Trip", itemIDs: [item], now: now)
        #expect(try await groups.groupIDsNeedingBrief(now: now).isEmpty)                         // debounced
        #expect(try await groups.groupIDsNeedingBrief(now: now.addingTimeInterval(601)) == [id])

        let inputs = try #require(try await groups.briefInputs(for: id))
        #expect(inputs.members.map(\.id) == [item])
        let brief = GroupBrief(title: "Trip", overview: "One item.", producer: "test", isProvisional: true)
        try await groups.saveBrief(brief, inputsHash: inputs.hash, version: 0, toGroup: id, now: now)
        #expect(try await groups.groupIDsNeedingBrief(now: now.addingTimeInterval(601)).isEmpty)
        #expect(try await groups.group(id: id)?.brief == brief)

        // A new member changes the inputs; asking for a brief skips the debounce.
        let second = try await fixture.insertItem("B")
        try await groups.addItems([second], to: id, now: now.addingTimeInterval(700))
        #expect(try await groups.groupIDsNeedingBrief(now: now.addingTimeInterval(800)).isEmpty)
        try await groups.requestBrief(id)
        #expect(try await groups.groupIDsNeedingBrief(now: now.addingTimeInterval(800)) == [id])

        // Provisional briefs are rewritten once the model is available.
        #expect(try await groups.groupIDsWithStaleBriefs(below: 1) == [id])
    }

    @Test func ungroupedVectorsLeaveOutGroupedAndOldItems() async throws {
        let grouped = try await fixture.insertItem("Grouped")
        let free = try await fixture.insertItem("Free")
        let old = try await fixture.insertItem("Old", daysAgo: 120)
        for id in [grouped, free, old] {
            try await fixture.items.saveEmbedding([1, 0], modelID: "m#1", forItem: id)
        }
        try await groups.createGroup(title: "G", itemIDs: [grouped], now: now)
        let vectors = try await groups.ungroupedVectors(modelID: "m#1", since: now.addingTimeInterval(-90 * 86_400))
        #expect(vectors.map(\.itemID) == [free])

        let byGroup = try await groups.memberVectors(modelID: "m#1")
        #expect(byGroup.values.map(\.count) == [1])
    }

    @Test func itemContextListsGroupsAndActions() async throws {
        let item = try await fixture.insertItem("Ramen")
        try await groups.createGroup(title: "Food", itemIDs: [item], now: now)
        try await fixture.actions.add(title: "Book a table", itemID: item, now: now)
        try await fixture.actions.dismiss(SuggestedAction(title: "Visit Ramen", itemID: item), now: now)

        let context = try #require(try await firstValue(groups.context(forItem: item)))
        #expect(context.groups.map(\.displayTitle) == ["Food"])
        #expect(context.actions.map(\.title) == ["Book a table"])
        #expect(context.knownActionTitles == ["book a table", "visit ramen"])
    }
}
