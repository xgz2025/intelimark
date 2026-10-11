import Foundation
import Testing
import GRDB
import Model
import Library
@testable import Sync

/// Triggers record every local change once, and stamp user edits field by field.
struct ChangeTrackingTests {
    let device: TestDevice

    init() throws {
        device = try TestDevice("A", root: temporaryDirectory())
    }

    @Test func localChangesAreRecordedOncePerRecord() async throws {
        let id = try await device.addItem("Aeron chair")
        let first = try #require(try await device.pending().first)
        #expect(first.key == RecordKey("Item", id))
        #expect(!first.isDeletion)

        try await device.execute("UPDATE item SET note = 'For the study' WHERE id = ?", [id])
        let pending = try await device.pending()
        #expect(pending.count == 1)
        #expect(pending[0].seq > first.seq)
    }

    @Test func userEditsAreStampedFieldByField() async throws {
        let id = try await device.addItem("Aeron chair")
        #expect(try await device.fieldTimes(RecordKey("Item", id)).isEmpty)

        try await device.items.setStatus(.active, forItem: id)
        try await device.items.setIntent(.buy, forItem: id)
        let times = try await device.fieldTimes(RecordKey("Item", id))
        #expect(Set(times.keys) == ["status", "intent"])
    }

    @Test func aiResultsStampTheirLayerNotTheUsersFields() async throws {
        let id = try await device.addItem("Aeron chair")
        let understanding = Understanding(
            title: "Herman Miller Aeron", summary: "An office chair.", semanticKind: .product,
            likelyIntent: .buy, keywords: ["chair"], producer: "test"
        )
        try await device.items.applyUnderstanding(understanding, toItem: id, version: 2)
        let times = try await device.fieldTimes(RecordKey("Item", id))
        #expect(Set(times.keys) == ["derivedVersion"])
    }

    @Test func deletionsAreRecorded() async throws {
        let actionID = try await device.actions.add(title: "Measure the desk")
        try await device.actions.delete(actionID)
        let pending = try await device.pending()
        #expect(pending.map(\.key) == [RecordKey("Action", actionID)])
        #expect(pending.first?.isDeletion == true)
    }

    @Test func columnsThatStayOnTheDeviceAreNotSent() async throws {
        let actionID = try await device.actions.add(title: "Measure the desk")
        let change = try #require(try await device.pending().first)
        try await device.store.didSend(saved: [SentChange(key: change.key, seq: change.seq, systemFields: nil)], deleted: [])
        #expect(try await device.pending().isEmpty)

        try await device.execute("UPDATE action SET reminderID = 'x-apple-reminder://1' WHERE id = ?", [actionID])
        #expect(try await device.pending().isEmpty)
    }

    @Test func aSendOnlyClearsTheChangeItCarried() async throws {
        let id = try await device.addItem("Aeron chair")
        let sent = try #require(try await device.pending().first)
        try await device.execute("UPDATE item SET note = 'Edited while sending' WHERE id = ?", [id])
        try await device.store.didSend(saved: [SentChange(key: sent.key, seq: sent.seq, systemFields: nil)], deleted: [])
        #expect(try await device.pending().map(\.key) == [RecordKey("Item", id)])
    }

    @Test func membershipsTheUserMadeAreStampedWhenCreated() async throws {
        let itemID = try await device.addItem("Ichiran")
        let groupID = try await device.groups.createGroup(title: "Tokyo", itemIDs: [itemID])
        let times = try await device.fieldTimes(RecordKey("Membership", "\(groupID)/\(itemID)"))
        #expect(Set(times.keys) == ["origin", "locked", "excluded"])

        let otherID = try await device.addItem("Afuri")
        try await device.groups.suggestMembership(itemID: otherID, groupID: groupID, score: 0.8)
        #expect(try await device.fieldTimes(RecordKey("Membership", "\(groupID)/\(otherID)")).isEmpty)
    }

    @Test func recordsFromTheServerAreNotSentBack() async throws {
        let record = SyncRecord(key: RecordKey("Group", "01JGROUP"), fields: [
            "id": .text("01JGROUP"), "kind": .text("manual"), "state": .text("accepted"), "userTitle": .text("Kyoto"),
            "briefVersion": .integer(0), "status": .text("active"),
            "createdAt": .text("2026-10-01 09:00:00.000"), "updatedAt": .text("2026-10-01 09:00:00.000"),
            "syncFieldTimes": .text("{}"),
        ], systemFields: Data("1".utf8))
        try await device.store.apply([record])
        #expect(try await device.groups.group(id: "01JGROUP")?.userTitle == "Kyoto")
        #expect(try await device.pending().isEmpty)
    }

    @Test func itemsKeptOnThisDeviceAreNeverSent() async throws {
        try await device.addItem("Private notes", scope: .local)
        let outgoing = try await device.store.outgoing()
        #expect(outgoing.count == 1)
        #expect(outgoing.first?.record == nil)
    }
}
