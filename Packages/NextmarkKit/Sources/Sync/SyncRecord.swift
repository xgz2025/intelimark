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

/// Names one synced row: its record type and its key (Library/SyncCatalog.swift).
public struct RecordKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public var recordType: String
    public var recordName: String

    public init(_ recordType: String, _ recordName: String) {
        self.recordType = recordType
        self.recordName = recordName
    }

    public var description: String { "\(recordType):\(recordName)" }

    public init?(_ description: String) {
        guard let colon = description.firstIndex(of: ":") else { return nil }
        recordType = String(description[..<colon])
        recordName = String(description[description.index(after: colon)...])
    }
}

/// A column value as SQLite stores it. Encoded with its type, so an integer never
/// comes back as a real (which would make two devices disagree forever).
public enum SyncValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    init(_ value: DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let int): self = .integer(int)
        case .double(let double): self = .real(double)
        case .string(let string): self = .text(string)
        case .blob(let data): self = .blob(data)
        }
    }

    var databaseValue: DatabaseValue {
        switch self {
        case .null: .null
        case .integer(let int): int.databaseValue
        case .real(let double): double.databaseValue
        case .text(let string): string.databaseValue
        case .blob(let data): data.databaseValue
        }
    }

    var stringValue: String? {
        if case .text(let string) = self { string } else { nil }
    }

    var intValue: Int64? {
        if case .integer(let int) = self { int } else { nil }
    }
}

extension SyncValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case i, r, s, b
    }

    public init(from decoder: any Decoder) throws {
        if try decoder.singleValueContainer().decodeNil() {
            self = .null
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let int = try container.decodeIfPresent(Int64.self, forKey: .i) {
            self = .integer(int)
        } else if let double = try container.decodeIfPresent(Double.self, forKey: .r) {
            self = .real(double)
        } else if let string = try container.decodeIfPresent(String.self, forKey: .s) {
            self = .text(string)
        } else if let data = try container.decodeIfPresent(Data.self, forKey: .b) {
            self = .blob(data)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown value"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if case .null = self {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null: break
        case .integer(let int): try container.encode(int, forKey: .i)
        case .real(let double): try container.encode(double, forKey: .r)
        case .text(let string): try container.encode(string, forKey: .s)
        case .blob(let data): try container.encode(data, forKey: .b)
        }
    }
}

/// One row as it travels to and from iCloud.
public struct SyncRecord: Sendable, Equatable, Codable {
    public var key: RecordKey
    /// Every synced column, including the `syncFieldTimes` stamps.
    public var fields: [String: SyncValue]
    /// The server's system fields (change tag), opaque to us. Nil for a record the
    /// server hasn't seen.
    public var systemFields: Data?
    /// An attachment's file, when it travels with the record.
    public var fileURL: URL?

    public init(key: RecordKey, fields: [String: SyncValue], systemFields: Data? = nil, fileURL: URL? = nil) {
        self.key = key
        self.fields = fields
        self.systemFields = systemFields
        self.fileURL = fileURL
    }

    public func encodedFields() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(fields)
    }

    public static func decodeFields(_ data: Data) throws -> [String: SyncValue] {
        try JSONDecoder().decode([String: SyncValue].self, from: data)
    }
}

/// A local change waiting to be sent.
public struct PendingChange: Sendable, Hashable {
    public let key: RecordKey
    public let isDeletion: Bool
    public let seq: Int64
}

/// A pending change, ready to send.
public struct OutgoingChange: Sendable {
    public let key: RecordKey
    public let seq: Int64
    public let isDeletion: Bool
    /// What to save; nil for a deletion, or when the row is gone or stays on this device.
    public let record: SyncRecord?
}

/// What the server confirmed: clears the change it carried, unless the row changed again since.
public struct SentChange: Sendable {
    public let key: RecordKey
    public let seq: Int64
    public let systemFields: Data?

    public init(key: RecordKey, seq: Int64, systemFields: Data?) {
        self.key = key
        self.seq = seq
        self.systemFields = systemFields
    }
}

/// What applying remote records changed here.
public struct SyncApplyResult: Sendable, Equatable {
    /// Items created or changed by another device: they need vectors here.
    public var changedItemIDs: Set<String> = []
    public var deletedItemIDs: Set<String> = []

    public init() {}

    public var isEmpty: Bool { changedItemIDs.isEmpty && deletedItemIDs.isEmpty }

    public mutating func merge(_ other: SyncApplyResult) {
        changedItemIDs.formUnion(other.changedItemIDs)
        deletedItemIDs.formUnion(other.deletedItemIDs)
        changedItemIDs.subtract(deletedItemIDs)
    }
}
