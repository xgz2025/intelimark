//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import GRDB

extension LibraryDatabase {
    /// Schema v1 follows Docs/architecture.md §4.2. Tables for later milestones
    /// (groups, actions, moments, AI sessions) are created now so those features
    /// ship as additive changes rather than migrations of user data.
    ///
    /// v1 is still edited in place: nothing has shipped, and debug builds erase the
    /// database when the schema changes. Once 1.0 ships, changes become new migrations.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("updatedAt", .datetime).notNull()
                t.column("surface", .text).notNull()
                t.column("sourceApp", .text)
                t.column("capturedOn", .text).notNull()
                t.column("canonicalURL", .text).indexed()
                t.column("contentHash", .text)
                // Source facts (immutable after capture)
                t.column("sourceTitle", .text)
                t.column("text", .text)
                t.column("anchor", .text)            // JSON SelectionAnchor
                t.column("pageContext", .text)       // JSON PageContext
                // Derived (AI and extractors)
                t.column("aiTitle", .text)
                t.column("summary", .text)
                t.column("imageDescription", .text)
                t.column("ocrText", .text)
                t.column("contentText", .text)       // readable page text, PDF text
                t.column("siteName", .text)
                t.column("heroImageURL", .text)
                t.column("imageLabels", .text).notNull().defaults(to: "[]")
                t.column("barcodes", .text).notNull().defaults(to: "[]")
                t.column("structuredKind", .text)    // from schema.org; wins over the model's guess
                t.column("typedFields", .text)       // JSON TypedFields
                t.column("extractVersion", .integer).notNull().defaults(to: 0)
                t.column("semanticKind", .text)
                t.column("suggestedIntent", .text)
                t.column("keywords", .text).notNull().defaults(to: "[]")
                t.column("dates", .text).notNull().defaults(to: "[]")      // JSON [ItemDate]
                t.column("places", .text).notNull().defaults(to: "[]")     // JSON [ItemPlace]
                t.column("derivedVersion", .integer).notNull().defaults(to: 0)
                // User layer (never overwritten by AI)
                t.column("userTitle", .text)
                t.column("note", .text)
                t.column("intent", .text)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("lastOpenedAt", .datetime)
                t.column("syncScope", .text).notNull().defaults(to: "cloud")
                // Screenshot Rescue: the Photos asset it came from, while it's still there (local only).
                t.column("sourceAssetID", .text).indexed()
            }

            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.tokenizer = .unicode61()
                t.column("sourceTitle")
                t.column("userTitle")
                t.column("aiTitle")
                t.column("summary")
                t.column("note")
                t.column("text")
                t.column("ocrText")
                t.column("imageDescription")
                t.column("contentText")
                t.column("siteName")
                t.column("imageLabels")
                t.column("places")
            }

            try db.create(table: "attachment") { t in
                t.primaryKey("id", .text)                    // <itemID>-<index>: the same on every device
                t.column("itemID", .text).notNull().indexed().references("item", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("byteSize", .integer)
                t.column("syncPolicy", .text).notNull()
            }

            try db.create(table: "highlight") { t in
                t.primaryKey("id", .text)
                t.column("itemID", .text).notNull().indexed().references("item", onDelete: .cascade)
                t.column("anchor", .text)
                t.column("quote", .text).notNull()
                t.column("color", .text)
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "itemGroup") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()            // manual · smart · plan · workstream
                t.column("state", .text).notNull().indexed() // suggested · accepted · dismissed
                t.column("userTitle", .text)
                t.column("aiTitle", .text)
                t.column("emoji", .text)
                t.column("color", .text)
                t.column("goal", .text)
                t.column("targetDate", .datetime)
                t.column("brief", .text)                     // JSON GroupBrief
                t.column("briefVersion", .integer).notNull().defaults(to: 0)
                t.column("briefInputsHash", .text)
                t.column("briefUpdatedAt", .datetime)
                t.column("status", .text).notNull()          // active · done
                t.column("outcome", .text)                   // what came of it, noted when done (PRD A5)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "membership") { t in
                t.column("groupID", .text).notNull().references("itemGroup", onDelete: .cascade)
                t.column("itemID", .text).notNull().indexed().references("item", onDelete: .cascade)
                t.column("origin", .text).notNull()          // user · ai
                t.column("score", .double)
                t.column("locked", .boolean).notNull().defaults(to: false)
                // The user took the item out: kept so the AI never suggests it again.
                t.column("excluded", .boolean).notNull().defaults(to: false)
                t.column("addedAt", .datetime).notNull()
                t.primaryKey(["groupID", "itemID"])
            }

            try db.create(table: "action") { t in
                t.primaryKey("id", .text)
                t.column("itemID", .text).indexed().references("item", onDelete: .cascade)
                t.column("groupID", .text).indexed().references("itemGroup", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("dueAt", .datetime)
                t.column("status", .text).notNull().indexed() // open · done · dismissed
                t.column("origin", .text).notNull()          // user · aiSuggested · aiAccepted
                t.column("reminderID", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }

            try db.create(table: "moment") { t in
                t.primaryKey("id", .text)
                t.column("targetID", .text).notNull().indexed()
                t.column("targetKind", .text).notNull()      // item · group
                t.column("trigger", .text).notNull()         // JSON
                t.column("state", .text).notNull()
                t.column("deliveredAt", .datetime)
            }

            // Local only: how the user answered each notification, so Moment types they
            // keep dismissing are muted (PRD M5, Docs/architecture.md §8).
            try db.create(table: "notificationLedger") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("reason", .text).notNull().indexed() // eventStart · deadline · actionDue · weeklyReview…
                t.column("targetID", .text).notNull()
                t.column("outcome", .text).notNull()          // opened · done · snoozed · dismissed
                t.column("recordedAt", .datetime).notNull()
            }

            // Recorded for every item from 1.0; Recap reads it (Docs/ai_sessions_spec.md §2).
            try db.create(table: "activitySpan") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemID", .text).notNull().indexed().references("item", onDelete: .cascade)
                t.column("start", .datetime).notNull().indexed()
                t.column("end", .datetime).notNull()
                t.column("source", .text).notNull()          // observed · exportTimestamp · agentLog
            }

            try db.create(table: "sessionMeta") { t in
                t.primaryKey("itemID", .text).references("item", onDelete: .cascade)
                t.column("tool", .text).notNull()
                t.column("conversationKey", .text).notNull()
                t.column("privateURL", .text)
                t.column("workingDirectory", .text)
                t.column("repo", .text)
                t.column("turnCount", .integer).notNull().defaults(to: 0)
                t.column("lastTurnHash", .text)
                t.column("adapterVersion", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["tool", "conversationKey"])
            }

            // Local only (never synced).
            try db.create(table: "embedding") { t in
                t.column("itemID", .text).notNull().references("item", onDelete: .cascade)
                t.column("modelID", .text).notNull()
                t.column("vector", .blob).notNull()
                t.primaryKey(["itemID", "modelID"])
            }

            try db.create(table: "job") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemID", .text).notNull().indexed()
                t.column("stage", .integer).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("notBefore", .datetime).notNull().indexed()
            }

            // Local only: Photos screenshots deleted from the library for good, so Screenshot
            // Rescue doesn't bring them back while they're still in Photos.
            try db.create(table: "ignoredAsset") { t in
                t.primaryKey("assetID", .text)
            }

            // Local only: items and groups the on-device model (or embedding model)
            // can't handle, so they aren't tried again at every launch. Tried again
            // after an OS update, which may bring a model that can.
            try db.create(table: "modelSkip") { t in
                t.column("subjectID", .text).notNull()
                t.column("stage", .text).notNull()
                t.column("osVersion", .text).notNull()
                t.primaryKey(["subjectID", "stage"])
            }

            // iCloud sync bookkeeping and change tracking (Docs/architecture.md §4.3).
            try SyncCatalog.createSchema(db)
        }

        // Reminders chosen for one show or trip (Docs/save_types.md); NULL uses the defaults.
        migrator.registerMigration("v2-reminders") { db in
            try db.alter(table: "item") { t in
                t.add(column: "reminders", .text)
            }
            // The change-tracking triggers list the item's columns: make them again.
            try SyncCatalog.recreateTriggers(forTable: "item", in: db)
        }

        // The price a product is wanted at ("tell me when it's under ¥299").
        migrator.registerMigration("v3-target-price") { db in
            try db.alter(table: "item") { t in
                t.add(column: "targetPrice", .double)
            }
            try SyncCatalog.recreateTriggers(forTable: "item", in: db)
        }
        return migrator
    }
}
