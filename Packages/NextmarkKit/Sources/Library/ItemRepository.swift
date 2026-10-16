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
import Model

/// Reads and writes items. UI code observes through `AsyncThrowingStream`s so
/// feature modules never import GRDB.
public struct ItemRepository: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func item(id: String) async throws -> ItemRecord? {
        try await database.writer.read { db in try ItemRecord.fetchOne(db, key: id) }
    }

    /// Live list of items with the given statuses, newest first.
    public func items(withStatus statuses: [ItemStatus] = [.inbox, .active]) -> AsyncThrowingStream<[ItemRecord], any Error> {
        let rawStatuses = statuses.map(\.rawValue)
        return database.observe { db in
            try ItemRecord
                .filter(rawStatuses.contains(Column("status")))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// The Inbox: items in play, without the older screenshots a rescue brought in
    /// (they have their own screen, and would bury new saves).
    public func inboxItems() -> AsyncThrowingStream<[ItemRecord], any Error> {
        database.observe { db in
            try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .filter(!(Column("surface") == CaptureSurface.screenshotImport.rawValue && Column("status") == ItemStatus.active.rawValue))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// The newest items still in play (inbox or active).
    public func recentItems(limit: Int = 30) async throws -> [ItemRecord] {
        try await database.writer.read { db in
            try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Live view of one item; nil once it is deleted.
    public func observeItem(id: String) -> AsyncThrowingStream<ItemRecord?, any Error> {
        database.observe { db in try ItemRecord.fetchOne(db, key: id) }
    }

    /// A user-layer change: done, faded, trashed… (PRD A5, M6).
    public func setStatus(_ status: ItemStatus, forItem id: String, now: Date = Date()) async throws {
        try await setStatus(status, forItems: [id], now: now)
    }

    /// Several items at once (a selection in the Inbox), in one transaction.
    public func setStatus(_ status: ItemStatus, forItems ids: [String], now: Date = Date()) async throws {
        try await database.writer.write { db in
            for id in ids {
                guard var item = try ItemRecord.fetchOne(db, key: id), item.status != status else { continue }
                item.status = status
                item.updatedAt = now
                try item.update(db)
            }
        }
    }

    /// Changes whenever any item is added, changed or deleted: lists that aren't
    /// observed queries (search results) refresh on it.
    public func revisions() -> AsyncThrowingStream<String, any Error> {
        database.observe { db in
            let row = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS count, MAX(updatedAt) AS latest FROM item")
            let count: Int = row?["count"] ?? 0
            let latest: String? = row?["latest"]
            return "\(count)|\(latest ?? "")"
        }
    }

    /// Shows and trips still ahead (or under way), soonest first: the Upcoming list.
    public func upcomingItems(now: @escaping @Sendable () -> Date = Date.init) -> AsyncThrowingStream<[ItemRecord], any Error> {
        database.observe { db in
            let candidates = try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .filter(Column("dates") != "[]" || Column("typedFields") != nil)
                .fetchAll(db)
            let current = now()
            return candidates
                .compactMap { item -> (ItemRecord, Date)? in item.nextDate(after: current).map { (item, $0.date) } }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }
    }

    /// Moves shows and trips that are over to Done, from the morning after: their
    /// date has passed, and there's nothing left to do with them. Returns what
    /// each moved item was before, for Undo.
    @discardableResult
    public func finishPastShowsAndTrips(now: Date = Date(), calendar: Calendar = .current) async throws -> [String: ItemStatus] {
        let startOfToday = calendar.startOfDay(for: now)
        return try await database.writer.write { db in
            let candidates = try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .filter(Column("dates") != "[]" || Column("typedFields") != nil)
                .fetchAll(db)
            var finished: [String: ItemStatus] = [:]
            for var item in candidates {
                guard item.saveType == .show || item.saveType == .travel,
                      let end = item.endsAt, end < startOfToday,
                      try Self.openActionCount(db, itemID: item.id) == 0
                else { continue }
                finished[item.id] = item.status
                item.status = .done
                item.updatedAt = now
                try item.update(db)
            }
            return finished
        }
    }

    static func openActionCount(_ db: Database, itemID: String) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM action WHERE itemID = ? AND status = 'open'", arguments: [itemID]) ?? 0
    }

    /// Live list of finished items, most recently finished first.
    public func doneItems() -> AsyncThrowingStream<[ItemRecord], any Error> {
        database.observe { db in
            try ItemRecord
                .filter(Column("status") == ItemStatus.done.rawValue)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    /// The user's answer to "why did you save this?" (PRD pillar 1). Nil clears it.
    public func setIntent(_ intent: Intent?, forItem id: String, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return }
            item.intent = intent
            item.updatedAt = now
            try item.update(db)
        }
    }

    /// The person's own title; nil or blank goes back to the automatic one.
    public func setTitle(_ title: String?, forItem id: String, now: Date = Date()) async throws {
        try await editUserLayer(id, now: now) { $0.userTitle = Self.cleaned(title) }
    }

    /// The reminders for one show or trip; nil goes back to the defaults for its kind.
    public func setReminders(_ reminders: [ReminderTime]?, forItem id: String, now: Date = Date()) async throws {
        try await editUserLayer(id, now: now) { $0.reminders = reminders }
    }

    /// The price a product is wanted at; nil (or zero) removes it.
    public func setTargetPrice(_ price: Double?, forItem id: String, now: Date = Date()) async throws {
        try await editUserLayer(id, now: now) { $0.targetPrice = price.flatMap { $0 > 0 ? $0 : nil } }
    }

    /// The person's note; nil or blank removes it.
    public func setNote(_ note: String?, forItem id: String, now: Date = Date()) async throws {
        try await editUserLayer(id, now: now) { $0.note = Self.cleaned(note) }
    }

    private func editUserLayer(_ id: String, now: Date, _ edit: @escaping @Sendable (inout ItemRecord) -> Void) async throws {
        try await database.writer.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return }
            let before = item
            edit(&item)
            guard item != before else { return }
            item.updatedAt = now
            try item.update(db)
        }
    }

    static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    public func attachments(forItem id: String) async throws -> [AttachmentRecord] {
        try await database.writer.read { db in
            try AttachmentRecord.filter(Column("itemID") == id).order(Column("id")).fetchAll(db)
        }
    }

    /// Writes the Extract stage's facts. Source facts are only filled when missing
    /// (a page title never replaces the one captured); the user layer is untouched.
    /// Read-modify-write in one transaction, so a concurrent edit can't be lost.
    /// - Returns: For a product, what its price did: a page read again (a Safari
    ///   refresh, say) records the price it shows now.
    @discardableResult
    public func applyExtraction(_ extraction: Extraction, toItem id: String, version: Int, now: Date = Date()) async throws -> PriceCheckOutcome? {
        try await database.writer.write { db -> PriceCheckOutcome? in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return nil }
            let earlier = item.typedFields?.product
            item.sourceTitle = item.sourceTitle ?? extraction.title
            item.siteName = extraction.siteName ?? item.siteName
            item.heroImageURL = extraction.heroImageURL?.absoluteString ?? item.heroImageURL
            item.contentText = extraction.contentText
            item.ocrText = extraction.ocrText
            item.imageLabels = extraction.imageLabels
            item.barcodes = extraction.barcodes
            item.structuredKind = extraction.structured?.kind
            item.typedFields = Self.keepingPriceHistory(extraction.typedFields, from: item.typedFields, savedAt: item.createdAt, now: now)
            if let kind = extraction.structured?.kind {
                item.semanticKind = kind
            }
            item.extractVersion = version
            item.updatedAt = now
            try item.update(db)
            return Self.outcome(from: earlier, to: item.typedFields?.product)
        }
    }

    static func outcome(from earlier: ProductFields?, to current: ProductFields?) -> PriceCheckOutcome? {
        guard let price = current?.price else { return nil }
        guard let before = earlier?.price, earlier?.currency == current?.currency else { return .found(price) }
        if price < before - 0.005 { return .dropped(from: before, to: price, currency: current?.currency) }
        if price > before + 0.005 { return .rose(from: before, to: price, currency: current?.currency) }
        return .unchanged(price)
    }

    /// A product's first price is its price when saved, the start of its history. Read
    /// again, its page's price is recorded on top of the history so far.
    static func keepingPriceHistory(_ fields: TypedFields?, from previous: TypedFields?, savedAt: Date, now: Date) -> TypedFields? {
        guard var fields, var product = fields.product else { return fields }
        if var earlier = previous?.product, earlier.priceHistory?.isEmpty == false {
            if let price = product.price {
                earlier.record(price: price, currency: product.currency ?? earlier.currency, at: now)
            }
            earlier.name = product.name ?? earlier.name
            earlier.description = product.description ?? earlier.description
            earlier.imageURL = product.imageURL ?? earlier.imageURL
            earlier.store = product.store ?? earlier.store
            earlier.brand = product.brand ?? earlier.brand
            earlier.availability = product.availability ?? earlier.availability
            product = earlier
        } else if let price = product.price, product.originalPrice == nil {
            product.originalPrice = price
            product.priceHistory = [PricePoint(at: savedAt, price: price)]
            product.checkedAt = savedAt
        }
        fields.product = product
        return fields
    }

    /// Writes the Understand stage's output into the derived layer only, so a user
    /// edit made while the model was running is never overwritten. Facts declared
    /// by the page's own schema.org data win: its kind beats the model's guess, and
    /// its dates and places come first. Read-modify-write in one transaction.
    public func applyUnderstanding(_ understanding: Understanding, toItem id: String, version: Int, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return }
            // An empty title means the understander had none to give.
            item.aiTitle = understanding.title.isEmpty ? nil : understanding.title
            item.summary = understanding.summary
            item.semanticKind = item.structuredKind ?? understanding.semanticKind
            item.suggestedIntent = understanding.likelyIntent
            item.keywords = understanding.keywords
            if let description = understanding.imageDescription {
                item.imageDescription = description
            }
            // What the model read of a trip, when nothing exact did.
            if let trip = understanding.trip, item.typedFields?.trip == nil {
                var fields = item.typedFields ?? TypedFields()
                fields.trip = trip
                item.typedFields = fields
            }
            item.dates = FactMerge.dates(structured: item.typedFields?.structuredDates ?? [], inferred: understanding.dates)
            item.places = FactMerge.places(structured: item.typedFields?.structuredPlaces ?? [], inferred: understanding.places)
            item.derivedVersion = version
            item.updatedAt = now
            try item.update(db)
        }
    }

    /// Links saved since `since` whose page never arrived (saved offline, say), with
    /// nothing queued for them.
    public func linkIDsNeedingExtraction(below version: Int, since: Date, limit: Int = 100) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM item
                    WHERE kind = ? AND extractVersion < ? AND status <> 'trashed' AND createdAt > ?
                      AND NOT EXISTS (SELECT 1 FROM job WHERE job.itemID = item.id)
                    ORDER BY createdAt DESC
                    LIMIT ?
                    """,
                arguments: [ItemKind.link.rawValue, version, since, limit]
            )
        }
    }

    /// Items whose understanding is older than `version` (or provisional, version 0)
    /// and that have no enrichment job pending — the backlog to re-run when the
    /// on-device model becomes available or the prompt changes.
    public func itemIDsNeedingUnderstanding(below version: Int, limit: Int = 200) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM item
                    WHERE derivedVersion < ? AND status <> 'trashed'
                      AND NOT EXISTS (SELECT 1 FROM job WHERE job.itemID = item.id)
                      AND \(LibraryDatabase.notSkipped(.understand, column: "item.id"))
                    ORDER BY createdAt DESC
                    LIMIT ?
                    """,
                arguments: [version, LibraryDatabase.osVersion, limit]
            )
        }
    }
}
