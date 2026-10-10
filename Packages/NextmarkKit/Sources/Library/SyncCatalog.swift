import Foundation
import GRDB

/// How each synced table maps to a CloudKit record, and how its columns merge
/// (Docs/architecture.md §4.3). Every column falls in one layer:
///
/// - **user** columns: the later edit wins, field by field. Local edits are stamped
///   in the row's `syncFieldTimes` by triggers.
/// - **derived** layers (AI and extractors): the higher version wins as a whole; on a
///   tie the later write wins.
/// - **latest** columns (timestamps): the later value wins.
/// - **local** columns: never leave the device.
/// - everything else is written once (identity and source facts): the server's copy wins.
public struct SyncTable: Sendable {
    public struct Parent: Sendable {
        public let column: String
        public let recordType: String
    }

    public struct DerivedLayer: Sendable {
        /// The `syncFieldTimes` key stamped when any of the layer's columns change.
        public let stampKey: String
        /// The column whose higher value wins; nil to compare stamps only.
        public let versionColumn: String?
        public let columns: [String]
    }

    public let recordType: String
    public let table: String
    public let keyColumns: [String]
    /// Rows a record can't exist without; records that arrive first wait for them.
    public let parents: [Parent]
    public let userColumns: [String]
    public let derivedLayers: [DerivedLayer]
    public let latestColumns: [String]
    public let localColumns: [String]
    /// SQL condition for rows that sync; the others stay on this device.
    public let sendCondition: String?
    /// SQL condition under which a remote deletion is refused and the row sent again:
    /// the user's decisions outlive the AI's.
    public let keepCondition: String?
    /// SQL condition (on `NEW`) for stamping user columns on insert: a row the user
    /// made must beat the same row the AI made on another device.
    public let stampOnInsert: String?

    public static let fieldTimesColumn = "syncFieldTimes"

    /// The record name: the key columns joined with "/". Keys never contain "/" or ":".
    public func recordName(_ values: [String]) -> String {
        values.joined(separator: "/")
    }

    public func keyValues(_ recordName: String) -> [String]? {
        let parts = recordName.split(separator: "/", maxSplits: keyColumns.count - 1, omittingEmptySubsequences: false)
        guard parts.count == keyColumns.count else { return nil }
        return parts.map(String.init)
    }

    public var keyCondition: String {
        keyColumns.map { "\($0) = ?" }.joined(separator: " AND ")
    }

    public func isWriteOnce(_ column: String) -> Bool {
        !userColumns.contains(column) && !latestColumns.contains(column) && !localColumns.contains(column)
            && !derivedLayers.contains { $0.columns.contains(column) } && column != Self.fieldTimesColumn
    }
}

public enum SyncCatalog {
    static let cloudItems = "SELECT id FROM item WHERE syncScope = 'cloud'"

    /// In the order records are applied: parents first.
    public static let tables: [SyncTable] = [
        SyncTable(
            recordType: "Item", table: "item", keyColumns: ["id"], parents: [],
            userColumns: ["userTitle", "note", "intent", "status", "pinned"],
            derivedLayers: [
                .init(stampKey: "extractVersion", versionColumn: "extractVersion", columns: [
                    "ocrText", "contentText", "siteName", "heroImageURL", "imageLabels", "barcodes",
                    "structuredKind", "typedFields", "extractVersion",
                ]),
                .init(stampKey: "derivedVersion", versionColumn: "derivedVersion", columns: [
                    "aiTitle", "summary", "imageDescription", "semanticKind", "suggestedIntent",
                    "keywords", "dates", "places", "derivedVersion",
                ]),
            ],
            latestColumns: ["updatedAt", "lastOpenedAt"],
            localColumns: [],
            sendCondition: "syncScope = 'cloud'",
            keepCondition: nil,
            stampOnInsert: nil
        ),
        SyncTable(
            recordType: "Group", table: "itemGroup", keyColumns: ["id"], parents: [],
            userColumns: ["kind", "state", "userTitle", "emoji", "color", "goal", "targetDate", "status", "outcome"],
            derivedLayers: [
                .init(stampKey: "briefVersion", versionColumn: "briefVersion", columns: [
                    "aiTitle", "brief", "briefVersion", "briefInputsHash", "briefUpdatedAt",
                ]),
            ],
            latestColumns: ["updatedAt"],
            localColumns: [],
            sendCondition: nil,
            keepCondition: nil,
            stampOnInsert: nil
        ),
        SyncTable(
            recordType: "Attachment", table: "attachment", keyColumns: ["id"],
            parents: [.init(column: "itemID", recordType: "Item")],
            userColumns: [], derivedLayers: [], latestColumns: [], localColumns: [],
            sendCondition: "itemID IN (\(cloudItems))",
            keepCondition: nil,
            stampOnInsert: nil
        ),
        SyncTable(
            recordType: "Membership", table: "membership", keyColumns: ["groupID", "itemID"],
            parents: [.init(column: "groupID", recordType: "Group"), .init(column: "itemID", recordType: "Item")],
            userColumns: ["origin", "locked", "excluded"],
            derivedLayers: [.init(stampKey: "score", versionColumn: nil, columns: ["score"])],
            latestColumns: [],
            localColumns: [],
            sendCondition: "itemID IN (\(cloudItems))",
            keepCondition: "locked = 1 OR excluded = 1",
            stampOnInsert: "NEW.locked = 1 OR NEW.excluded = 1"
        ),
        SyncTable(
            recordType: "Action", table: "action", keyColumns: ["id"],
            parents: [.init(column: "itemID", recordType: "Item"), .init(column: "groupID", recordType: "Group")],
            userColumns: ["title", "dueAt", "status", "origin", "completedAt", "groupID"],
            derivedLayers: [],
            latestColumns: [],
            // The Reminders link is per device (EventKit identifiers differ).
            localColumns: ["reminderID"],
            sendCondition: "itemID IS NULL OR itemID IN (\(cloudItems))",
            keepCondition: nil,
            stampOnInsert: nil
        ),
    ]

    public static func table(forRecordType recordType: String) -> SyncTable? {
        tables.first { $0.recordType == recordType }
    }

    public static func table(named name: String) -> SyncTable? {
        tables.first { $0.table == name }
    }
}

// MARK: - Schema

extension SyncCatalog {
    /// Bookkeeping tables (all local) and the triggers that record every local change.
    static func createSchema(_ db: Database) throws {
        // `applying` is set while remote records are written, so they aren't sent back;
        // `counter` orders changes, so a send only clears the change it carried.
        try db.create(table: "syncControl") { t in
            t.primaryKey("id", .integer).check { $0 == 1 }
            t.column("applying", .integer).notNull().defaults(to: 0)
            t.column("counter", .integer).notNull().defaults(to: 0)
        }
        try db.execute(sql: "INSERT INTO syncControl (id) VALUES (1)")

        // Local changes waiting to be sent: one row per record.
        try db.create(table: "syncChange") { t in
            t.column("recordType", .text).notNull()
            t.column("recordName", .text).notNull()
            t.column("isDeletion", .boolean).notNull()
            t.column("seq", .integer).notNull()
            t.primaryKey(["recordType", "recordName"])
        }

        // The server's system fields (change tag) for each record.
        try db.create(table: "syncMetadata") { t in
            t.column("recordType", .text).notNull()
            t.column("recordName", .text).notNull()
            t.column("systemFields", .blob)
            t.primaryKey(["recordType", "recordName"])
        }

        // Records that arrived before their parent.
        try db.create(table: "syncOrphan") { t in
            t.column("recordType", .text).notNull()
            t.column("recordName", .text).notNull()
            t.column("waitingFor", .text).notNull().indexed()
            t.column("payload", .blob).notNull()
            t.primaryKey(["recordType", "recordName"])
        }

        // The sync engine's own state.
        try db.create(table: "syncState") { t in
            t.primaryKey("key", .text)
            t.column("value", .blob).notNull()
        }

        for table in tables {
            try createTriggers(for: table, columns: db.columns(in: table.table).map(\.name), in: db)
        }
    }

    static let notApplying = "(SELECT applying FROM syncControl) = 0"
    static let now = "strftime('%Y-%m-%d %H:%M:%f', 'now')"

    static func recordNameSQL(_ table: SyncTable, row: String) -> String {
        table.keyColumns.map { "\(row).\($0)" }.joined(separator: " || '/' || ")
    }

    static func recordChangeSQL(_ table: SyncTable, row: String, isDeletion: Bool) -> String {
        """
        UPDATE syncControl SET counter = counter + 1;
        INSERT INTO syncChange (recordType, recordName, isDeletion, seq)
        VALUES ('\(table.recordType)', \(recordNameSQL(table, row: row)), \(isDeletion ? 1 : 0), (SELECT counter FROM syncControl))
        ON CONFLICT (recordType, recordName) DO UPDATE SET isDeletion = excluded.isDeletion, seq = excluded.seq;
        """
    }

    static func stampSQL(_ table: SyncTable, keys: [String]) -> String {
        let times = keys.reduce(SyncTable.fieldTimesColumn) { json, key in "json_set(\(json), '$.\(key)', \(now))" }
        let match = table.keyColumns.map { "\($0) = NEW.\($0)" }.joined(separator: " AND ")
        return "UPDATE \(table.table) SET \(SyncTable.fieldTimesColumn) = \(times) WHERE \(match);"
    }

    static func changed(_ columns: [String]) -> String {
        columns.map { "NEW.\($0) IS NOT OLD.\($0)" }.joined(separator: " OR ")
    }

    static func createTriggers(for table: SyncTable, columns: [String], in db: Database) throws {
        let name = table.table
        let synced = columns.filter { !table.localColumns.contains($0) && $0 != SyncTable.fieldTimesColumn }

        try db.execute(sql: """
            CREATE TRIGGER sync_\(name)_insert AFTER INSERT ON \(name) WHEN \(notApplying)
            BEGIN
            \(recordChangeSQL(table, row: "NEW", isDeletion: false))
            END
            """)
        try db.execute(sql: """
            CREATE TRIGGER sync_\(name)_update AFTER UPDATE ON \(name) WHEN \(notApplying) AND (\(changed(synced)))
            BEGIN
            \(recordChangeSQL(table, row: "NEW", isDeletion: false))
            END
            """)
        try db.execute(sql: """
            CREATE TRIGGER sync_\(name)_delete AFTER DELETE ON \(name) WHEN \(notApplying)
            BEGIN
            \(recordChangeSQL(table, row: "OLD", isDeletion: true))
            END
            """)

        guard columns.contains(SyncTable.fieldTimesColumn) else { return }
        for column in table.userColumns {
            try db.execute(sql: """
                CREATE TRIGGER sync_\(name)_stamp_\(column) AFTER UPDATE OF \(column) ON \(name)
                WHEN \(notApplying) AND NEW.\(column) IS NOT OLD.\(column)
                BEGIN
                \(stampSQL(table, keys: [column]))
                END
                """)
        }
        for layer in table.derivedLayers {
            try db.execute(sql: """
                CREATE TRIGGER sync_\(name)_stamp_\(layer.stampKey) AFTER UPDATE OF \(layer.columns.joined(separator: ", ")) ON \(name)
                WHEN \(notApplying) AND (\(changed(layer.columns)))
                BEGIN
                \(stampSQL(table, keys: [layer.stampKey]))
                END
                """)
        }
        if let condition = table.stampOnInsert, !table.userColumns.isEmpty {
            try db.execute(sql: """
                CREATE TRIGGER sync_\(name)_stamp_insert AFTER INSERT ON \(name)
                WHEN \(notApplying) AND (\(condition))
                BEGIN
                \(stampSQL(table, keys: table.userColumns))
                END
                """)
        }
    }
}

/// The user's iCloud settings (PRD P1, P2), shared by Settings and the sync engine.
public enum SyncSettings {
    public enum Key {
        public static let enabled = "sync.enabled"
        public static let originals = "sync.originals"
        public static let lastSyncedAt = "sync.lastSyncedAt"
        public static let status = "sync.status"
    }

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.enabled) as? Bool ?? true
    }

    /// Full original files sync unless turned off; they can take a lot of iCloud space.
    public static func syncsOriginals(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.originals) as? Bool ?? true
    }
}
