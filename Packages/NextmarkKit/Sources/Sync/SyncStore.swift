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
import Library

/// The database side of sync, independent of CloudKit: which local changes are
/// waiting, the records that carry them, and how records from other devices are
/// written. `CloudSync` drives it with CKSyncEngine; tests drive it with a fake server.
public struct SyncStore: Sendable {
    public let database: LibraryDatabase
    /// Where item files live (`<itemsDirectory>/<itemID>/<fileName>`).
    public let itemsDirectory: URL
    private let syncsOriginals: @Sendable () -> Bool

    public init(
        database: LibraryDatabase,
        itemsDirectory: URL,
        syncsOriginals: @escaping @Sendable () -> Bool = { SyncSettings.syncsOriginals() }
    ) {
        self.database = database
        self.itemsDirectory = itemsDirectory
        self.syncsOriginals = syncsOriginals
    }

    // MARK: Outgoing

    /// Changes made after `seq`, oldest first.
    public func pendingChanges(after seq: Int64 = 0) async throws -> [PendingChange] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT recordType, recordName, isDeletion, seq FROM syncChange WHERE seq > ? ORDER BY seq",
                arguments: [seq]
            ).map { row in
                PendingChange(key: RecordKey(row["recordType"], row["recordName"]), isDeletion: row["isDeletion"], seq: row["seq"])
            }
        }
    }

    /// The pending changes for `keys` (all of them when nil), with the records to save.
    public func outgoing(_ keys: [RecordKey]? = nil) async throws -> [OutgoingChange] {
        let directory = itemsDirectory
        let originals = syncsOriginals()
        return try await database.writer.read { db in
            let changes: [Row]
            if let keys {
                changes = try keys.compactMap { key in
                    try Row.fetchOne(
                        db,
                        sql: "SELECT * FROM syncChange WHERE recordType = ? AND recordName = ?",
                        arguments: [key.recordType, key.recordName]
                    )
                }
            } else {
                changes = try Row.fetchAll(db, sql: "SELECT * FROM syncChange ORDER BY seq")
            }
            return try changes.map { row in
                let key = RecordKey(row["recordType"], row["recordName"])
                let isDeletion: Bool = row["isDeletion"]
                let record = isDeletion ? nil : try Self.record(for: key, in: db, itemsDirectory: directory, originals: originals)
                return OutgoingChange(key: key, seq: row["seq"], isDeletion: isDeletion, record: record)
            }
        }
    }

    static func record(for key: RecordKey, in db: Database, itemsDirectory: URL, originals: Bool) throws -> SyncRecord? {
        guard let table = SyncCatalog.table(forRecordType: key.recordType), let values = table.keyValues(key.recordName) else {
            return nil
        }
        let condition = table.sendCondition.map { " AND (\($0))" } ?? ""
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM \(table.table) WHERE \(table.keyCondition)\(condition)",
            arguments: StatementArguments(values)
        ) else { return nil }

        var fields: [String: SyncValue] = [:]
        for (column, value) in row where !table.localColumns.contains(column) {
            fields[column] = SyncValue(value)
        }
        fields[SyncTable.fieldTimesColumn] = .text(try stamps(for: key, in: db) ?? "{}")
        var record = SyncRecord(key: key, fields: fields, systemFields: try systemFields(for: key, in: db))
        if table.recordType == "Attachment",
           let file = fileLocation(fields, itemsDirectory: itemsDirectory),
           FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            let policy = fields["syncPolicy"]?.stringValue.flatMap(AttachmentSyncPolicy.init(rawValue:)) ?? .ifEnabled
            if policy == .always || (policy == .ifEnabled && originals) {
                record.fileURL = file
            }
        }
        return record
    }

    static func stamps(for key: RecordKey, in db: Database) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT times FROM syncStamp WHERE recordType = ? AND recordName = ?",
            arguments: [key.recordType, key.recordName]
        )
    }

    static func systemFields(for key: RecordKey, in db: Database) throws -> Data? {
        try Data.fetchOne(
            db,
            sql: "SELECT systemFields FROM syncMetadata WHERE recordType = ? AND recordName = ?",
            arguments: [key.recordType, key.recordName]
        )
    }

    /// Where an attachment's file lives. Nil for a name that could escape the item's folder.
    static func fileLocation(_ fields: [String: SyncValue], itemsDirectory: URL) -> URL? {
        guard let itemID = fields["itemID"]?.stringValue, let fileName = fields["fileName"]?.stringValue,
              !itemID.isEmpty, !itemID.contains("/"), !itemID.hasPrefix("."),
              !fileName.isEmpty, !fileName.contains("/"), !fileName.hasPrefix(".")
        else { return nil }
        return itemsDirectory.appending(path: itemID, directoryHint: .isDirectory).appending(path: fileName)
    }

    /// The server took these. A change is cleared only if the row hasn't changed again since.
    public func didSend(saved: [SentChange], deleted: [SentChange]) async throws {
        try await database.writer.write { db in
            for change in saved {
                try Self.storeSystemFields(change.systemFields, for: change.key, in: db)
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE recordType = ? AND recordName = ? AND isDeletion = 0 AND seq <= ?",
                    arguments: [change.key.recordType, change.key.recordName, change.seq]
                )
            }
            for change in deleted {
                try Self.forget(change.key, in: db)
                // Records that arrived for a parent we deleted will never find it.
                try db.execute(sql: "DELETE FROM syncOrphan WHERE waitingFor = ?", arguments: [change.key.description])
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE recordType = ? AND recordName = ? AND isDeletion = 1 AND seq <= ?",
                    arguments: [change.key.recordType, change.key.recordName, change.seq]
                )
            }
        }
    }

    /// Changes with nothing to send: the row is gone, or it stays on this device.
    public func discard(_ changes: [OutgoingChange]) async throws {
        guard !changes.isEmpty else { return }
        try await database.writer.write { db in
            for change in changes {
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE recordType = ? AND recordName = ? AND seq <= ?",
                    arguments: [change.key.recordType, change.key.recordName, change.seq]
                )
            }
        }
    }

    /// The server lost these records (e.g. its zone was reset): send them as new.
    public func forgetSystemFields(_ keys: [RecordKey]) async throws {
        guard !keys.isEmpty else { return }
        try await database.writer.write { db in
            for key in keys { try Self.forget(key, in: db) }
        }
    }

    // MARK: Incoming

    /// Writes records and deletions from the server. Parents go first; a record whose
    /// parent hasn't arrived waits for it. A merge that differs from the server's copy
    /// is queued to be sent back.
    @discardableResult
    public func apply(_ records: [SyncRecord], deletions: [RecordKey] = []) async throws -> SyncApplyResult {
        guard !records.isEmpty || !deletions.isEmpty else { return SyncApplyResult() }
        let directory = itemsDirectory
        return try await database.writer.write { db in
            try db.execute(sql: "UPDATE syncControl SET applying = 1")
            var result = SyncApplyResult()
            let order = Dictionary(uniqueKeysWithValues: SyncCatalog.tables.enumerated().map { ($1.recordType, $0) })
            let sorted = records.sorted { order[$0.key.recordType, default: .max] < order[$1.key.recordType, default: .max] }
            for record in sorted {
                // Files land first: an asset's temporary file is gone once this returns.
                if let url = record.fileURL { Self.placeFile(url, for: record, itemsDirectory: directory) }
                try Self.apply(record, in: db, result: &result)
            }
            try Self.adoptOrphans(in: db, result: &result)
            // Parents first: a group's deletion takes its memberships and actions with it.
            let sortedDeletions = deletions.sorted {
                order[$0.recordType, default: .max] < order[$1.recordType, default: .max]
            }
            for key in sortedDeletions {
                try Self.applyDeletion(key, in: db, result: &result)
            }
            try db.execute(sql: "UPDATE syncControl SET applying = 0")
            return result
        }
    }

    static func apply(_ record: SyncRecord, in db: Database, result: inout SyncApplyResult) throws {
        guard let table = SyncCatalog.table(forRecordType: record.key.recordType),
              let values = table.keyValues(record.key.recordName)
        else { return }   // a type from a newer version of the app
        let key = record.key

        // A local deletion that hasn't gone out yet wins.
        if try Bool.fetchOne(
            db,
            sql: "SELECT isDeletion FROM syncChange WHERE recordType = ? AND recordName = ?",
            arguments: [key.recordType, key.recordName]
        ) == true {
            try storeSystemFields(record.systemFields, for: key, in: db)
            return
        }

        for parent in table.parents {
            guard let parentID = record.fields[parent.column]?.stringValue,
                  let parentTable = SyncCatalog.table(forRecordType: parent.recordType)
            else { continue }
            let exists = try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM \(parentTable.table) WHERE id = ?)", arguments: [parentID]
            ) ?? false
            if !exists {
                var parked = record
                parked.fileURL = nil
                try db.execute(
                    sql: """
                        INSERT INTO syncOrphan (recordType, recordName, waitingFor, payload) VALUES (?, ?, ?, ?)
                        ON CONFLICT (recordType, recordName) DO UPDATE SET waitingFor = excluded.waitingFor, payload = excluded.payload
                        """,
                    arguments: [key.recordType, key.recordName, RecordKey(parent.recordType, parentID).description,
                                try JSONEncoder().encode(parked)]
                )
                return
            }
        }

        let columns = try db.columns(in: table.table).map(\.name).filter { !table.localColumns.contains($0) }
        let local = try Row.fetchOne(
            db, sql: "SELECT * FROM \(table.table) WHERE \(table.keyCondition)", arguments: StatementArguments(values)
        )
        var localFields: [String: SyncValue]?
        if let local {
            var fields: [String: SyncValue] = [:]
            for (column, value) in local where !table.localColumns.contains(column) {
                fields[column] = SyncValue(value)
            }
            fields[SyncTable.fieldTimesColumn] = .text(try stamps(for: key, in: db) ?? "{}")
            localFields = fields
        }
        let merged = localFields.map { SyncMerge.merge(local: $0, remote: record.fields, table: table) } ?? record.fields

        try db.inSavepoint {
            do {
                try upsert(merged, into: table, columns: columns, in: db)
            } catch {
                // A record this version can't store (e.g. a required column it lacks): skip it.
                return .rollback
            }
            if let times = merged[SyncTable.fieldTimesColumn]?.stringValue, times != "{}" {
                try db.execute(
                    sql: """
                        INSERT INTO syncStamp (recordType, recordName, times) VALUES (?, ?, ?)
                        ON CONFLICT (recordType, recordName) DO UPDATE SET times = excluded.times
                        """,
                    arguments: [key.recordType, key.recordName, times]
                )
            }
            try storeSystemFields(record.systemFields, for: key, in: db)
            if localFields != nil, SyncMerge.differs(merged, from: record.fields, columns: columns + [SyncTable.fieldTimesColumn]) {
                try markChanged(key, in: db)
            } else {
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE recordType = ? AND recordName = ? AND isDeletion = 0",
                    arguments: [key.recordType, key.recordName]
                )
            }
            // Our own saves come back too; only a row that actually changed here counts.
            if table.recordType == "Item",
               localFields.map({ SyncMerge.differs(merged, from: $0, columns: columns) }) ?? true {
                result.changedItemIDs.insert(key.recordName)
            }
            return .commit
        }
    }

    static func upsert(_ fields: [String: SyncValue], into table: SyncTable, columns: [String], in db: Database) throws {
        let present = columns.filter { fields[$0] != nil }
        let updates = present.filter { !table.keyColumns.contains($0) }
        let conflict = updates.isEmpty
            ? "DO NOTHING"
            : "DO UPDATE SET " + updates.map { "\($0) = excluded.\($0)" }.joined(separator: ", ")
        try db.execute(
            sql: """
                INSERT INTO \(table.table) (\(present.joined(separator: ", "))) VALUES (\(present.map { _ in "?" }.joined(separator: ", ")))
                ON CONFLICT (\(table.keyColumns.joined(separator: ", "))) \(conflict)
                """,
            arguments: StatementArguments(present.map { fields[$0]?.databaseValue ?? .null })
        )
    }

    /// Records whose parents have arrived since they were parked.
    static func adoptOrphans(in db: Database, result: inout SyncApplyResult) throws {
        var progress = true
        while progress {
            progress = false
            for row in try Row.fetchAll(db, sql: "SELECT * FROM syncOrphan") {
                guard let parent = RecordKey(row["waitingFor"] as String),
                      let table = SyncCatalog.table(forRecordType: parent.recordType),
                      try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM \(table.table) WHERE id = ?)",
                                        arguments: [parent.recordName]) == true
                else { continue }
                try db.execute(
                    sql: "DELETE FROM syncOrphan WHERE recordType = ? AND recordName = ?",
                    arguments: [row["recordType"] as String, row["recordName"] as String]
                )
                if let record = try? JSONDecoder().decode(SyncRecord.self, from: row["payload"] as Data) {
                    try apply(record, in: db, result: &result)
                }
                progress = true
            }
        }
    }

    static func applyDeletion(_ key: RecordKey, in db: Database, result: inout SyncApplyResult) throws {
        guard let table = SyncCatalog.table(forRecordType: key.recordType), let values = table.keyValues(key.recordName) else {
            return
        }
        try forget(key, in: db)
        try db.execute(
            sql: "DELETE FROM syncOrphan WHERE (recordType = ? AND recordName = ?) OR waitingFor = ?",
            arguments: [key.recordType, key.recordName, key.description]
        )
        let arguments = StatementArguments(values)
        guard try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM \(table.table) WHERE \(table.keyCondition))", arguments: arguments
        ) == true else {
            try db.execute(sql: "DELETE FROM syncChange WHERE recordType = ? AND recordName = ?",
                           arguments: [key.recordType, key.recordName])
            return
        }
        if let keep = table.keepCondition,
           try Bool.fetchOne(db, sql: "SELECT \(keep) FROM \(table.table) WHERE \(table.keyCondition)", arguments: arguments) == true {
            // The user decided this one; another device's AI doesn't get to remove it.
            try markChanged(key, in: db)
            return
        }
        try db.execute(sql: "DELETE FROM \(table.table) WHERE \(table.keyCondition)", arguments: arguments)
        try db.execute(sql: "DELETE FROM syncChange WHERE recordType = ? AND recordName = ?",
                       arguments: [key.recordType, key.recordName])
        if table.recordType == "Item" { result.deletedItemIDs.insert(key.recordName) }
    }

    static func placeFile(_ url: URL, for record: SyncRecord, itemsDirectory: URL) {
        guard record.key.recordType == "Attachment",
              let destination = fileLocation(record.fields, itemsDirectory: itemsDirectory)
        else { return }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.copyItem(at: url, to: destination)
    }

    // MARK: Bookkeeping

    static func markChanged(_ key: RecordKey, in db: Database) throws {
        try db.execute(sql: "UPDATE syncControl SET counter = counter + 1")
        try db.execute(
            sql: """
                INSERT INTO syncChange (recordType, recordName, isDeletion, seq)
                VALUES (?, ?, 0, (SELECT counter FROM syncControl))
                ON CONFLICT (recordType, recordName) DO UPDATE SET isDeletion = 0, seq = excluded.seq
                """,
            arguments: [key.recordType, key.recordName]
        )
    }

    static func storeSystemFields(_ data: Data?, for key: RecordKey, in db: Database) throws {
        guard let data else { return }
        try db.execute(
            sql: """
                INSERT INTO syncMetadata (recordType, recordName, systemFields) VALUES (?, ?, ?)
                ON CONFLICT (recordType, recordName) DO UPDATE SET systemFields = excluded.systemFields
                """,
            arguments: [key.recordType, key.recordName, data]
        )
    }

    static func forget(_ key: RecordKey, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM syncMetadata WHERE recordType = ? AND recordName = ?",
            arguments: [key.recordType, key.recordName]
        )
    }

    /// Queues every row of `recordTypes` (all synced types when nil) to be sent.
    public func markAllChanged(recordTypes: [String]? = nil) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE syncControl SET counter = counter + 1")
            for table in SyncCatalog.tables where recordTypes?.contains(table.recordType) ?? true {
                let name = table.keyColumns.map { "\(table.table).\($0)" }.joined(separator: " || '/' || ")
                try db.execute(
                    sql: """
                        INSERT INTO syncChange (recordType, recordName, isDeletion, seq)
                        SELECT ?, \(name), 0, (SELECT counter FROM syncControl) FROM \(table.table) WHERE true
                        ON CONFLICT (recordType, recordName) DO UPDATE SET isDeletion = 0, seq = excluded.seq
                        """,
                    arguments: [table.recordType]
                )
            }
        }
    }

    /// A new account, or a server that lost our zone: forget everything the server
    /// told us and send the whole library again. Local data is never deleted.
    public func resetServerState() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM syncMetadata")
            try db.execute(sql: "DELETE FROM syncOrphan")
            try db.execute(sql: "DELETE FROM syncState")
            try db.execute(sql: "DELETE FROM syncChange WHERE isDeletion = 1")
        }
        try await markAllChanged()
    }

    /// Increments with every local change; observe it to learn there is something to send.
    public func changeCounter() -> AsyncThrowingStream<Int64, any Error> {
        let writer = database.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let observation = ValueObservation.tracking { db in
                        try Int64.fetchOne(db, sql: "SELECT counter FROM syncControl") ?? 0
                    }.removeDuplicates()
                    for try await value in observation.values(in: writer) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Engine state

    public func engineState() async throws -> Data? {
        try await database.writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = 'engine'")
        }
    }

    public func saveEngineState(_ data: Data) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO syncState (key, value) VALUES ('engine', ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                arguments: [data]
            )
        }
    }
}
