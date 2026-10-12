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
import Model
@testable import Library

struct ActionRepositoryTests {
    let fixture: LibraryFixture
    var actions: ActionRepository { fixture.actions }
    var now: Date { fixture.now }

    init() throws {
        fixture = try LibraryFixture()
    }

    @Test func nextActionsAreOrderedByDueDate() async throws {
        let item = try await fixture.insertItem("Concert")
        let group = try await fixture.groups.createGroup(title: "Kyoto", emoji: "🧳", now: now)
        let later = try await actions.add(title: "Pack", dueAt: now.addingTimeInterval(5 * 86_400), groupID: group, now: now)
        let sooner = try await actions.add(title: "Buy tickets", dueAt: now.addingTimeInterval(86_400), itemID: item, now: now)
        let anytime = try await actions.add(title: "Read reviews", now: now)

        let list = try #require(try await firstValue(actions.nextActions()))
        #expect(list.map(\.id) == [sooner, later, anytime])
        #expect(list[0].itemTitle == "Concert")
        #expect(list[1].groupTitle == "Kyoto")
        #expect(list[1].groupEmoji == "🧳")
    }

    @Test func doneActionsAndDoneGroupsLeaveTheList() async throws {
        let group = try await fixture.groups.createGroup(title: "Old plan", now: now)
        try await actions.add(title: "Group step", groupID: group, now: now)
        let single = try await actions.add(title: "Single step", now: now)
        try await actions.setDone(true, forAction: single, now: now)
        try await fixture.groups.setStatus(.done, forGroup: group, now: now)
        #expect(try await firstValue(actions.nextActions())?.isEmpty == true)
    }

    @Test func finishingTheLastActionOffersToFinishItsItemAndGroup() async throws {
        let item = try await fixture.insertItem("Desk")
        let group = try await fixture.groups.createGroup(title: "Office", itemIDs: [item], now: now)
        let first = try await actions.add(title: "Measure", itemID: item, groupID: group, now: now)
        let second = try await actions.add(title: "Order", itemID: item, now: now)

        #expect(try await actions.setDone(true, forAction: first, now: now) == ActionCompletion(finishedGroupID: group))
        #expect(try await actions.setDone(true, forAction: second, now: now) == ActionCompletion(finishedItemID: item))

        // Already done items aren't offered again; undoing finishes nothing.
        try await fixture.items.setStatus(.done, forItem: item, now: now)
        try await actions.setDone(false, forAction: second, now: now)
        #expect(try await actions.setDone(true, forAction: second, now: now) == ActionCompletion())
    }

    @Test func suggestionsAreAcceptedOrRemembered() async throws {
        let item = try await fixture.insertItem("Aeron chair")
        let buy = SuggestedAction(title: "Buy Aeron chair", dueAt: now.addingTimeInterval(86_400), itemID: item)
        let read = SuggestedAction(title: "Read Aeron chair", itemID: item)
        try await actions.accept(buy, now: now)
        try await actions.dismiss(read, now: now)

        #expect(try await actions.knownTitles(itemIDs: [item]) == ["buy aeron chair", "read aeron chair"])
        let list = try #require(try await firstValue(actions.nextActions()))
        #expect(list.map(\.action.title) == ["Buy Aeron chair"])
        #expect(list.first?.action.origin == .aiAccepted)
        #expect(list.first?.action.dueAt == buy.dueAt)
    }

    @Test func actionsCanBeRenamedAndDeleted() async throws {
        let id = try await actions.add(title: "  Draft  ", now: now)
        try await actions.update(id, title: "Final", dueAt: nil)
        #expect(try await firstValue(actions.nextActions())?.map(\.action.title) == ["Final"])
        try await actions.delete(id)
        #expect(try await firstValue(actions.nextActions())?.isEmpty == true)
    }
}
