import Foundation
import Testing
import Library
@testable import Sync

/// Conflict policy (Docs/architecture.md §4.3): user fields by later edit, derived
/// layers by version, source facts written once.
struct SyncMergeTests {
    let item = SyncCatalog.table(forRecordType: "Item")!

    func times(_ times: [String: String]) -> SyncValue {
        SyncMerge.encode(times)
    }

    @Test func eachUserFieldKeepsItsLaterEdit() {
        let local: [String: SyncValue] = [
            "note": .text("For the study"), "status": .text("inbox"),
            "syncFieldTimes": times(["note": "2026-10-10 10:00:00.000"]),
        ]
        let remote: [String: SyncValue] = [
            "note": .text(""), "status": .text("done"),
            "syncFieldTimes": times(["status": "2026-10-10 11:00:00.000"]),
        ]
        let merged = SyncMerge.merge(local: local, remote: remote, table: item)
        #expect(merged["note"] == .text("For the study"))
        #expect(merged["status"] == .text("done"))
        #expect(SyncMerge.times(merged) == ["note": "2026-10-10 10:00:00.000", "status": "2026-10-10 11:00:00.000"])
        #expect(SyncMerge.differs(merged, from: remote, columns: ["note", "status", "syncFieldTimes"]))
    }

    @Test func theHigherDerivedVersionWinsWhateverItsAge() {
        let local: [String: SyncValue] = [
            "aiTitle": .text("Herman Miller Aeron"), "summary": .text("Model summary"), "derivedVersion": .integer(2),
            "syncFieldTimes": times(["derivedVersion": "2026-10-10 09:00:00.000"]),
        ]
        let remote: [String: SyncValue] = [
            "aiTitle": .text("Aeron chair"), "summary": .null, "derivedVersion": .integer(0),
            "syncFieldTimes": times(["derivedVersion": "2026-10-10 12:00:00.000"]),
        ]
        let merged = SyncMerge.merge(local: local, remote: remote, table: item)
        #expect(merged["aiTitle"] == .text("Herman Miller Aeron"))
        #expect(merged["summary"] == .text("Model summary"))
        #expect(merged["derivedVersion"] == .integer(2))
    }

    @Test func onAVersionTieTheLaterWriteWins() {
        let local: [String: SyncValue] = [
            "aiTitle": .text("Earlier"), "derivedVersion": .integer(2),
            "syncFieldTimes": times(["derivedVersion": "2026-10-10 09:00:00.000"]),
        ]
        let remote: [String: SyncValue] = [
            "aiTitle": .text("Later"), "derivedVersion": .integer(2),
            "syncFieldTimes": times(["derivedVersion": "2026-10-10 12:00:00.000"]),
        ]
        #expect(SyncMerge.merge(local: local, remote: remote, table: item)["aiTitle"] == .text("Later"))
        #expect(SyncMerge.merge(local: remote, remote: local, table: item)["aiTitle"] == .text("Later"))
    }

    @Test func sourceFactsAreWrittenOnceAndTimestampsKeepTheLatest() {
        let local: [String: SyncValue] = [
            "sourceTitle": .text("Aeron Chair – Herman Miller"), "kind": .text("link"),
            "lastOpenedAt": .text("2026-10-10 12:00:00.000"),
        ]
        let remote: [String: SyncValue] = [
            "sourceTitle": .null, "kind": .text("link"),
            "lastOpenedAt": .text("2026-10-09 08:00:00.000"),
        ]
        let merged = SyncMerge.merge(local: local, remote: remote, table: item)
        #expect(merged["sourceTitle"] == .text("Aeron Chair – Herman Miller"))
        #expect(merged["lastOpenedAt"] == .text("2026-10-10 12:00:00.000"))
    }

    @Test func mergingTheSameCopyChangesNothing() {
        let copy: [String: SyncValue] = [
            "note": .text("x"), "score": .real(0.5), "pinned": .integer(0),
            "syncFieldTimes": times(["note": "2026-10-10 10:00:00.000"]),
        ]
        let merged = SyncMerge.merge(local: copy, remote: copy, table: item)
        #expect(!SyncMerge.differs(merged, from: copy, columns: Array(copy.keys)))
    }

    @Test func valuesKeepTheirTypeInTransit() throws {
        let record = SyncRecord(key: RecordKey("Membership", "g/i"), fields: [
            "score": .real(3), "locked": .integer(1), "origin": .text("ai"), "excluded": .null, "blob": .blob(Data([1, 2])),
        ])
        let decoded = try SyncRecord.decodeFields(record.encodedFields())
        #expect(decoded == record.fields)
    }

    @Test func recordKeysReadBackFromTheirDescription() {
        let key = RecordKey("Membership", "01JG/01JI")
        #expect(RecordKey(key.description) == key)
        #expect(RecordKey("no-colon") == nil)
    }
}
