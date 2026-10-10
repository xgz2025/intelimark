import Foundation
import Testing
import CloudKit
@testable import Sync

struct CloudRecordCoderTests {
    let record = SyncRecord(
        key: RecordKey("Membership", "01JGROUP/01JITEM"),
        fields: ["groupID": .text("01JGROUP"), "itemID": .text("01JITEM"), "score": .real(0.82), "locked": .integer(1)]
    )

    @Test func recordsRoundTripThroughCloudKit() throws {
        let ckRecord = try CloudRecordCoder.ckRecord(from: record)
        #expect(ckRecord.recordType == "Membership")
        #expect(ckRecord.recordID.recordName == "Membership:01JGROUP/01JITEM")
        #expect(ckRecord.recordID.zoneID.zoneName == "Library")

        let decoded = try #require(try CloudRecordCoder.syncRecord(from: ckRecord))
        #expect(decoded.key == record.key)
        #expect(decoded.fields == record.fields)
        #expect(decoded.systemFields != nil)
    }

    @Test func savedSystemFieldsAreReused() throws {
        let first = try CloudRecordCoder.ckRecord(from: record)
        var next = record
        next.systemFields = CloudRecordCoder.systemFields(of: first)
        next.fields["locked"] = .integer(0)
        let second = try CloudRecordCoder.ckRecord(from: next)
        #expect(second.recordID == first.recordID)
        #expect(try CloudRecordCoder.syncRecord(from: second)?.fields["locked"] == .integer(0))
    }
}
