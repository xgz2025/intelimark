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
import Model

/// What the person says about the fields Laterwise read ("Correct?",
/// Docs/save_types.md): right, wrong in places, or not that kind of thing at all.
public enum FieldCorrection: Sendable, Equatable {
    /// The fields as read are right.
    case confirm
    /// "Not a Receipt": its fields go, and the guess isn't made again.
    case reject(SaveType)
    case trip(TripFields)
    case ticket(TicketFields)
    case receipt(ReceiptFields)
    case product(name: String?, price: Double?, currency: String?, store: String?)
}

extension ItemRecord {
    /// Whether the fields that make this item what it is were read by rules or a
    /// model, not stated by the item, and the person hasn't confirmed them yet.
    public var needsConfirmation: Bool {
        guard let fields = typedFields else { return false }
        switch saveType {
        case .travel: return fields.trip?.origin?.isUncertain ?? false
        case .show: return fields.ticket?.origin?.isUncertain ?? false
        case .receipt: return fields.receipt.map { $0.origin != .user } ?? false
        case .product: return fields.product?.price != nil && (fields.product?.origin?.isUncertain ?? false)
        case .article, .link, .other: return false
        }
    }
}

extension ItemRepository {
    /// Applies the person's correction. Their fields are marked as theirs, so reading
    /// the item again (a re-save, a newer extractor) keeps them.
    public func correct(_ correction: FieldCorrection, forItem id: String, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return }
            let fields = Self.corrected(item.typedFields ?? TypedFields(), by: correction, as: item.saveType, now: now)
            item.typedFields = fields
            // The item's dates follow its fields: a corrected departure, or none.
            var inferred = item.dates.filter { $0.source != .structured }
            if case .reject(.travel) = correction { inferred.removeAll { $0.role == .departure } }
            item.dates = FactMerge.dates(structured: fields.structuredDates, inferred: inferred)
            let places = item.places.filter { $0.source != .structured }
            item.places = FactMerge.places(structured: fields.structuredPlaces, inferred: places)
            item.updatedAt = now
            try item.update(db)
        }
    }

    static func corrected(_ fields: TypedFields, by correction: FieldCorrection, as type: SaveType, now: Date) -> TypedFields {
        var fields = fields
        switch correction {
        case .confirm:
            switch type {
            case .travel: fields.trip?.origin = .user
            case .show: fields.ticket?.origin = .user
            case .receipt: fields.receipt?.origin = .user
            case .product: fields.product?.origin = .user
            case .article, .link, .other: break
            }
        case .reject(let rejected):
            fields.rejected = Array(Set((fields.rejected ?? []) + [rejected.rawValue])).sorted()
            fields = Self.dropping(Set(fields.rejected ?? []), from: fields)
        case .trip(var trip):
            trip.origin = .user
            fields.trip = trip.legs.isEmpty ? nil : trip
            fields.rejected?.removeAll { $0 == SaveType.travel.rawValue }
        case .ticket(var ticket):
            ticket.origin = .user
            fields.ticket = ticket
            fields.rejected?.removeAll { $0 == SaveType.show.rawValue }
        case .receipt(var receipt):
            receipt.origin = .user
            fields.receipt = receipt
            fields.rejected?.removeAll { $0 == SaveType.receipt.rawValue }
        case .product(let name, let price, let currency, let store):
            var product = fields.product ?? ProductFields()
            product.name = name
            product.store = store
            if let price {
                Self.correctPrice(&product, to: price, currency: currency ?? product.currency, now: now)
            }
            product.origin = .user
            fields.product = product
            fields.rejected?.removeAll { $0 == SaveType.product.rawValue }
        }
        if fields.rejected?.isEmpty == true { fields.rejected = nil }
        return fields
    }

    /// A misread price is replaced, not recorded as a change: "↓ $50 since saved"
    /// must compare real prices.
    static func correctPrice(_ product: inout ProductFields, to price: Double, currency: String?, now: Date) {
        let sameCurrency = currency == nil || product.currency == nil || currency == product.currency
        var history = sameCurrency ? (product.priceHistory ?? []) : []
        if history.isEmpty {
            history = [PricePoint(at: product.checkedAt ?? now, price: price)]
        } else {
            history[history.count - 1].price = price
        }
        if history.count == 1 || product.originalPrice == nil || !sameCurrency {
            product.originalPrice = price
        }
        product.priceHistory = history
        product.price = price
        product.currency = currency ?? product.currency
        product.checkedAt = product.checkedAt ?? now
    }

    /// The fields read again, with the person's corrections kept: sections they
    /// edited or confirmed, and what they said the item isn't.
    static func keepingCorrections(_ fields: TypedFields?, from previous: TypedFields?) -> TypedFields? {
        guard let previous else { return fields }
        var kept = fields ?? TypedFields()
        if previous.trip?.origin == .user { kept.trip = previous.trip }
        if previous.ticket?.origin == .user { kept.ticket = previous.ticket }
        if previous.receipt?.origin == .user { kept.receipt = previous.receipt }
        if let earlier = previous.product, earlier.origin == .user {
            // The page's newer price is recorded (`keepingPriceHistory`); the name and
            // shop the person gave stay.
            var product = kept.product ?? earlier
            product.name = earlier.name
            product.store = earlier.store
            if kept.product?.origin?.isUncertain ?? true { product.origin = .user }
            kept.product = product
        }
        if let rejected = previous.rejected, !rejected.isEmpty {
            kept.rejected = rejected
            kept = dropping(Set(rejected), from: kept)
        }
        return fields == nil && kept == TypedFields() ? nil : kept
    }

    static func dropping(_ rejected: Set<String>, from fields: TypedFields) -> TypedFields {
        var fields = fields
        if rejected.contains(SaveType.travel.rawValue) { fields.trip = nil }
        if rejected.contains(SaveType.show.rawValue) {
            fields.ticket = nil
            fields.event = nil
        }
        if rejected.contains(SaveType.receipt.rawValue) { fields.receipt = nil }
        if rejected.contains(SaveType.product.rawValue) { fields.product = nil }
        return fields
    }
}
