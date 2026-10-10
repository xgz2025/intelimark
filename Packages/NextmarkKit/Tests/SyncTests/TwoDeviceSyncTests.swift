import Foundation
import Testing
import GRDB
import Model
import Library
@testable import Sync

/// Two devices syncing through a fake server (Docs/architecture.md §13).
struct TwoDeviceSyncTests {
    let root = temporaryDirectory()
    let cloud: FakeCloud
    let phone: TestDevice
    let mac: TestDevice

    init() throws {
        cloud = FakeCloud(filesDirectory: root.appending(path: "cloud"))
        phone = try TestDevice("phone", root: root)
        mac = try TestDevice("mac", root: root)
    }

    /// Syncs both devices until they agree, then checks nothing more goes up.
    func settle() async throws {
        for _ in 0..<3 {
            try await phone.sync(with: cloud)
            try await mac.sync(with: cloud)
        }
        #expect(try await phone.pending().isEmpty)
        #expect(try await mac.pending().isEmpty)
        let clock = await cloud.clock
        try await phone.sync(with: cloud)
        try await mac.sync(with: cloud)
        #expect(await cloud.clock == clock, "devices kept sending after they agreed")
    }

    @Test func itemsAndTheirFilesReachTheOtherDevice() async throws {
        let pdf = Data("%PDF-1.7 menu".utf8)
        let id = try await phone.addItem("Ichiran menu", note: "Try the spicy one", files: ["0-menu.pdf": pdf])
        try await phone.sync(with: cloud)
        let result = try await mac.sync(with: cloud)

        #expect(result.changedItemIDs == [id])
        let item = try #require(try await mac.items.item(id: id))
        #expect(item.displayTitle == "Ichiran menu")
        #expect(item.note == "Try the spicy one")
        let attachment = try #require(try await mac.items.attachments(forItem: id).first)
        #expect(attachment.fileName == "0-menu.pdf")
        let file = mac.itemsDirectory.appending(path: id).appending(path: "0-menu.pdf")
        #expect(try Data(contentsOf: file) == pdf)
        try await settle()
    }

    @Test func originalsStayHomeWhenTurnedOff() async throws {
        let ipad = try TestDevice("ipad", root: root, originals: false)
        let id = try await ipad.addItem("Scan", files: ["0-scan.pdf": Data("%PDF".utf8)])
        try await ipad.sync(with: cloud)
        try await mac.sync(with: cloud)

        #expect(try await mac.items.attachments(forItem: id).count == 1)
        #expect(await !cloud.hasFile(RecordKey("Attachment", "\(id)-00")))
        let file = mac.itemsDirectory.appending(path: id).appending(path: "0-scan.pdf")
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func editsToDifferentFieldsBothSurvive() async throws {
        let id = try await phone.addItem("Aeron chair")
        try await phone.sync(with: cloud)
        try await mac.sync(with: cloud)

        // Both edit while offline.
        try await phone.execute("UPDATE item SET note = 'Wait for the sale' WHERE id = ?", [id])
        try await mac.items.setStatus(.active, forItem: id)
        try await settle()

        for device in [phone, mac] {
            let item = try #require(try await device.items.item(id: id))
            #expect(item.note == "Wait for the sale")
            #expect(item.status == .active)
        }
    }

    @Test func theLaterEditToAFieldWins() async throws {
        let id = try await phone.addItem("Aeron chair")
        try await phone.sync(with: cloud)
        try await mac.sync(with: cloud)

        try await phone.items.setIntent(.buy, forItem: id)
        try await nextMillisecond()
        try await mac.items.setIntent(.read, forItem: id)
        try await settle()

        #expect(try await phone.items.item(id: id)?.intent == .read)
        #expect(try await mac.items.item(id: id)?.intent == .read)
    }

    @Test func theModelsResultReplacesAProvisionalOne() async throws {
        // The phone has no on-device model; the Mac does (PRD U6).
        let id = try await phone.addItem("aeron-chair.html")
        try await phone.sync(with: cloud)
        try await mac.sync(with: cloud)

        let model = Understanding(
            title: "Herman Miller Aeron", summary: "An office chair on sale.", semanticKind: .product,
            likelyIntent: .buy, keywords: ["chair"], producer: "foundation-models"
        )
        try await mac.items.applyUnderstanding(model, toItem: id, version: 2)
        try await nextMillisecond()
        // Later, but provisional: it must not replace the model's result.
        let heuristic = Understanding(
            title: "aeron-chair", summary: "", semanticKind: .other, likelyIntent: nil, keywords: [],
            producer: "heuristic", isProvisional: true
        )
        try await phone.items.applyUnderstanding(heuristic, toItem: id, version: 0)
        try await phone.execute("UPDATE item SET note = 'For the study' WHERE id = ?", [id])
        try await settle()

        for device in [phone, mac] {
            let item = try #require(try await device.items.item(id: id))
            #expect(item.aiTitle == "Herman Miller Aeron")
            #expect(item.derivedVersion == 2)
            #expect(item.note == "For the study")
        }
    }

    @Test func groupsMembersAndActionsTravelTogether() async throws {
        let ramen = try await phone.addItem("Ichiran")
        let sushi = try await phone.addItem("Sushi Dai")
        let groupID = try await phone.groups.createGroup(title: "Tokyo food", emoji: "🍜", itemIDs: [ramen, sushi])
        let actionID = try await phone.actions.add(title: "Book a table", itemID: sushi)
        try await settle()

        let group = try #require(try await mac.groups.group(id: groupID))
        #expect(group.userTitle == "Tokyo food")
        let members = try await mac.database.writer.read { db in
            try MembershipRecord.filter(Column("groupID") == groupID).fetchAll(db)
        }
        #expect(Set(members.map(\.itemID)) == [ramen, sushi])
        #expect(members.filter { !$0.locked }.isEmpty)
        #expect(try await mac.actions.openActions().map(\.action.id) == [actionID])

        // Done on the Mac, seen on the phone.
        _ = try await mac.actions.setDone(true, forAction: actionID)
        try await settle()
        #expect(try await phone.actions.openActions().isEmpty)
    }

    @Test func deletingAGroupRemovesItEverywhere() async throws {
        let itemID = try await phone.addItem("Ichiran")
        let groupID = try await phone.groups.createGroup(title: "Tokyo food", itemIDs: [itemID])
        try await settle()
        #expect(try await mac.groups.group(id: groupID) != nil)

        try await phone.groups.delete(groupID)
        try await settle()
        #expect(try await mac.groups.group(id: groupID) == nil)
        let memberships = try await mac.database.writer.read { db in try MembershipRecord.fetchCount(db) }
        #expect(memberships == 0)
        #expect(try await mac.items.item(id: itemID) != nil)
    }

    @Test func aMemberWaitsForItsGroupToArrive() async throws {
        let itemID = try await phone.addItem("Ichiran")
        let groupID = try await phone.groups.createGroup(title: "Tokyo food", itemIDs: [itemID])
        try await phone.sync(with: cloud)

        let membership = try #require(await cloud.record(RecordKey("Membership", "\(groupID)/\(itemID)")))
        let item = try #require(await cloud.record(RecordKey("Item", itemID)))
        let group = try #require(await cloud.record(RecordKey("Group", groupID)))
        // The membership comes in a batch of its own, before its group.
        try await mac.store.apply([membership, item])
        #expect(try await mac.database.writer.read { db in try MembershipRecord.fetchCount(db) } == 0)
        try await mac.store.apply([group])
        #expect(try await mac.database.writer.read { db in try MembershipRecord.fetchCount(db) } == 1)
        #expect(try await mac.pending().isEmpty)
    }

    @Test func anotherDevicesAICantRemoveWhatTheUserConfirmed() async throws {
        let itemID = try await phone.addItem("Ichiran")
        let groupID = try await phone.groups.createGroup(title: "Tokyo food")
        try await phone.groups.suggestMembership(itemID: itemID, groupID: groupID, score: 0.7)
        try await settle()

        try await mac.groups.confirmItem(itemID, in: groupID)
        // The phone's AI dropped its suggestion before hearing about the confirmation.
        let key = RecordKey("Membership", "\(groupID)/\(itemID)")
        try await mac.store.apply([], deletions: [key])
        #expect(try await mac.pending().map(\.key).contains(key))
        try await settle()

        for device in [phone, mac] {
            let membership = try await device.database.writer.read { db in
                try MembershipRecord.fetchOne(db, key: ["groupID": groupID, "itemID": itemID])
            }
            #expect(membership?.locked == true)
        }
    }

    @Test func aDeletionAfterAnotherDevicesEditWins() async throws {
        let actionID = try await phone.actions.add(title: "Book a table")
        try await settle()
        try await mac.actions.update(actionID, title: "Book a table for four", dueAt: nil)
        try await phone.actions.delete(actionID)
        try await mac.sync(with: cloud)
        // The deletion goes up after the edit and stands everywhere.
        try await phone.sync(with: cloud)
        try await settle()
        #expect(try await phone.actions.openActions().isEmpty)
        #expect(try await mac.actions.openActions().isEmpty)
    }

    @Test func aPendingDeletionIgnoresTheRecordItDeletes() async throws {
        let actionID = try await phone.actions.add(title: "Book a table")
        try await settle()
        try await mac.actions.update(actionID, title: "Book a table for four", dueAt: nil)
        try await mac.sync(with: cloud)
        try await phone.actions.delete(actionID)
        // The edit arrives before the phone has sent its deletion.
        let edited = try #require(await cloud.record(RecordKey("Action", actionID)))
        try await phone.store.apply([edited])
        #expect(try await phone.actions.openActions().isEmpty)
        try await settle()
        #expect(try await mac.actions.openActions().isEmpty)
    }

    @Test func itemsKeptOnThisDeviceNeverLeaveIt() async throws {
        try await phone.addItem("Private notes", scope: .local)
        try await settle()
        #expect(await cloud.recordCount == 0)
    }
}
