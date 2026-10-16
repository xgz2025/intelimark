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

/// What Check Price found.
public enum PriceCheckOutcome: Sendable, Equatable {
    case dropped(from: Double, to: Double, currency: String?)
    case rose(from: Double, to: Double, currency: String?)
    case unchanged(Double)
    /// First price seen.
    case found(Double)
    /// The page couldn't be read, or showed no price (it needs a browser, or a sign-in).
    case unavailable
}

/// Products saved to compare before buying (Docs/save_types.md): their prices over
/// time, and similar products kept together in a comparison group.
extension ItemRepository {
    /// Records a price seen for a product. Returns the price before it, if any.
    @discardableResult
    public func recordPrice(_ price: Double, currency: String?, forItem id: String, now: Date = Date()) async throws -> Double? {
        try await database.writer.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return nil }
            var fields = item.typedFields ?? TypedFields()
            var product = fields.product ?? ProductFields(name: item.displayTitle, store: item.siteName, origin: .page)
            let before = product.price
            product.record(price: price, currency: currency, at: now)
            fields.product = product
            item.typedFields = fields
            item.updatedAt = now
            try item.update(db)
            return before
        }
    }

    /// Notes a check that found no price, so it isn't tried again at once.
    public func markPriceChecked(forItem id: String, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id), var fields = item.typedFields, var product = fields.product else { return }
            product.checkedAt = now
            fields.product = product
            item.typedFields = fields
            try item.update(db)
        }
    }

    /// Products in play whose price was last checked before `checkedBefore`, oldest first.
    public func productIDsToCheck(checkedBefore cutoff: Date, limit: Int) async throws -> [String] {
        try await database.writer.read { db in
            try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .filter(Column("canonicalURL") != nil)
                .filter(Column("typedFields").like("%\"product\"%"))
                .fetchAll(db)
                .filter { $0.saveType == .product && ($0.typedFields?.product?.checkedAt ?? .distantPast) < cutoff }
                .sorted { ($0.typedFields?.product?.checkedAt ?? .distantPast) < ($1.typedFields?.product?.checkedAt ?? .distantPast) }
                .prefix(limit)
                .map(\.id)
        }
    }
}

extension GroupRepository {
    /// Puts a product with the similar products already saved: into their comparison
    /// group, or a new one with them. With `autoAccept` (Pro) it's a group straight
    /// away; otherwise a suggestion. Returns the group's ID, if any.
    @discardableResult
    public func groupSimilarProducts(itemID: String, autoAccept: Bool, now: Date = Date()) async throws -> String? {
        let match = try await database.writer.read { db -> (others: [String], groupID: String?, name: String)? in
            guard let item = try ItemRecord.fetchOne(db, key: itemID), item.saveType == .product else { return nil }
            let name = item.typedFields?.product?.name ?? item.displayTitle
            let others = try ItemRecord
                .filter([ItemStatus.inbox.rawValue, ItemStatus.active.rawValue].contains(Column("status")))
                .filter(Column("id") != itemID)
                .filter(Column("typedFields").like("%\"product\"%"))
                .fetchAll(db)
                .filter { $0.saveType == .product }
                .filter { ProductMatching.similarity(name, $0.typedFields?.product?.name ?? $0.displayTitle) >= ProductMatching.threshold }
                .map(\.id)
            guard !others.isEmpty else { return nil }
            // A group of the similar products that's still in play, and that the
            // person hasn't taken this product out of.
            let groupID = try String.fetchOne(db, sql: """
                SELECT membership.groupID FROM membership
                JOIN itemGroup ON itemGroup.id = membership.groupID
                WHERE membership.itemID IN (\(others.map { _ in "?" }.joined(separator: ",")))
                  AND membership.excluded = 0
                  AND itemGroup.state IN ('accepted', 'suggested') AND itemGroup.status = 'active'
                  AND NOT EXISTS (SELECT 1 FROM membership AS own WHERE own.groupID = membership.groupID AND own.itemID = ?)
                GROUP BY membership.groupID
                ORDER BY COUNT(*) DESC
                LIMIT 1
                """, arguments: StatementArguments(others + [itemID]))
            // Already with them (or taken out of their group): nothing to do.
            let alreadyGrouped = try Bool.fetchOne(db, sql: """
                SELECT EXISTS (
                    SELECT 1 FROM membership AS own
                    JOIN membership AS other ON other.groupID = own.groupID
                    WHERE own.itemID = ? AND other.itemID IN (\(others.map { _ in "?" }.joined(separator: ",")))
                )
                """, arguments: StatementArguments([itemID] + others)) ?? false
            return alreadyGrouped ? nil : (others, groupID, name)
        }
        guard let match else { return nil }
        if let groupID = match.groupID {
            try await suggestMembership(itemID: itemID, groupID: groupID, score: 1, now: now)
            if autoAccept { try await confirmItem(itemID, in: groupID, now: now) }
            return groupID
        }
        let title = ProductMatching.groupTitle(for: [match.name])
        let members = [itemID] + match.others
        if autoAccept {
            return try await createComparisonGroup(title: title, itemIDs: members, now: now)
        }
        return try await addSuggestedGroup(title: title, itemIDs: members, score: 1, now: now)
    }

    /// An accepted smart group, its members confirmed: Pro compares on its own.
    func createComparisonGroup(title: String, itemIDs: [String], now: Date) async throws -> String {
        let id = try await addSuggestedGroup(title: title, itemIDs: itemIDs, score: 1, now: now)
        try await acceptSuggestion(id, now: now)
        return id
    }
}

/// How alike two product names are: shared words (and, for Chinese and Japanese,
/// shared pairs of characters), as a share of the shorter name's.
public enum ProductMatching {
    public static let threshold = 0.4

    static let ignored: Set<String> = [
        "the", "and", "for", "with", "new", "men", "women", "mens", "womens", "unisex", "size", "color", "colour",
        "free", "shipping", "sale", "pack", "set", "inch", "in", "of", "a", "an", "-", "|", "&",
    ]

    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = tokens(lhs)
        let b = tokens(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }

    static func tokens(_ text: String) -> Set<String> {
        var result = Set<String>()
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let characters = Array(word)
            if characters.contains(where: isCJK) {
                // No spaces between words: compare pairs of characters.
                for index in characters.indices.dropLast() {
                    result.insert(String(characters[index...index + 1]))
                }
                if characters.count == 1 { result.insert(String(word)) }
            } else if word.count >= 2, !ignored.contains(String(word)) {
                result.insert(String(word))
            }
        }
        return result
    }

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    /// "Compare: Wool Coat": the product's name, short.
    static func groupTitle(for names: [String]) -> String {
        let name = names.first ?? ""
        let words = name.split(separator: " ").prefix(4).joined(separator: " ")
        let short = words.count > 32 ? String(words.prefix(31)) + "…" : words
        return String(localized: "Compare: \(short)")
    }
}

/// One product's address, however it was reached: shops add tracking and session
/// parameters, and Amazon puts the name in the path. Two links with the same key
/// are the same product (Safari refresh, Docs/save_types.md).
public enum ProductURL {
    /// Query parameters that say which product (or which variant) it is.
    static let identifyingParameters: Set<String> = [
        "id", "itemid", "item_id", "goods_id", "goodsid", "productid", "product_id", "pid", "sku", "skuid",
        "sku_id", "variant", "spuid", "spu_id", "asin",
    ]

    public static func key(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var host = components.host?.lowercased()
        else { return nil }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        let path = components.path
        // Amazon: /Some-Name/dp/B0ABC12345/ref=… → the ASIN.
        if host.contains("amazon."), let asin = path.firstMatch(of: #/(?:/dp/|/gp/product/|/gp/aw/d/)([A-Z0-9]{10})/#) {
            return "\(host)/dp/\(asin.output.1)"
        }
        let kept = (components.queryItems ?? [])
            .filter { identifyingParameters.contains($0.name.lowercased()) && !($0.value ?? "").isEmpty }
            .map { "\($0.name.lowercased())=\($0.value ?? "")" }
            .sorted()
        components.query = nil
        let trimmedPath = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return host + trimmedPath + (kept.isEmpty ? "" : "?" + kept.joined(separator: "&"))
    }
}

/// When a price change is worth a notification: it reached the person's target, or
/// (Pro) it dropped.
public enum PriceAlert: Sendable, Equatable {
    case reachedTarget(price: Double, target: Double)
    case dropped(from: Double, to: Double)

    public static func notice(for outcome: PriceCheckOutcome, target: Double?, includesDrops: Bool) -> PriceAlert? {
        let (before, after): (Double?, Double?) = switch outcome {
        case .dropped(let from, let to, _): (from, to)
        case .rose(let from, let to, _): (from, to)
        case .found(let price): (nil, price)
        case .unchanged, .unavailable: (nil, nil)
        }
        guard let after else { return nil }
        // Crossing the target, not sitting under it: said once, when it happens.
        if let target, after <= target, before.map({ $0 > target }) ?? true {
            return .reachedTarget(price: after, target: target)
        }
        if includesDrops, let before, after < before {
            return .dropped(from: before, to: after)
        }
        return nil
    }
}
