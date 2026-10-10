import Foundation
import CloudKit

/// Converts between `SyncRecord`s and `CKRecord`s. All of a record's columns travel
/// in one end-to-end encrypted field; an attachment's file travels as a `CKAsset`.
public enum CloudRecordCoder {
    /// One custom zone in the private database (Docs/architecture.md §4.3).
    public static let zoneID = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)
    static let fieldsKey = "fields"
    static let fileKey = "file"

    /// `<recordType>:<recordName>`, so a bare record ID still says what it names.
    public static func recordID(for key: RecordKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.description, zoneID: zoneID)
    }

    public static func key(for recordID: CKRecord.ID) -> RecordKey? {
        RecordKey(recordID.recordName)
    }

    public static func ckRecord(from record: SyncRecord) throws -> CKRecord {
        let recordID = Self.recordID(for: record.key)
        let ckRecord: CKRecord
        if let data = record.systemFields, let restored = Self.restore(data), restored.recordID == recordID {
            ckRecord = restored
        } else {
            ckRecord = CKRecord(recordType: record.key.recordType, recordID: recordID)
        }
        ckRecord.encryptedValues[fieldsKey] = try record.encodedFields()
        // Without a file, the server keeps whatever file another device sent.
        if let url = record.fileURL {
            ckRecord.setObject(CKAsset(fileURL: url), forKey: fileKey)
        }
        return ckRecord
    }

    public static func syncRecord(from ckRecord: CKRecord) throws -> SyncRecord? {
        guard let key = Self.key(for: ckRecord.recordID), key.recordType == ckRecord.recordType else { return nil }
        let data: Data? = ckRecord.encryptedValues[fieldsKey]
        guard let data else { return nil }
        return SyncRecord(
            key: key,
            fields: try SyncRecord.decodeFields(data),
            systemFields: Self.systemFields(of: ckRecord),
            fileURL: (ckRecord.object(forKey: fileKey) as? CKAsset)?.fileURL
        )
    }

    /// The record's change tag and metadata, without its values.
    public static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func restore(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}
