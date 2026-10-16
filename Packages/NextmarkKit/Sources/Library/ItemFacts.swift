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

/// One labeled fact on an item's screen, with where it came from, so a date or a
/// place is never a guess dressed up as a fact.
public struct ItemFact: Sendable, Equatable, Identifiable {
    public enum Label: String, Sendable, Equatable {
        case merchant, total, purchased, taken, location
        case author, publisher, published, created
        case price, priceWhenSaved, lowestPrice, priceChecked, store, brand, availability
        case starts, doors, ends, venue, address, phone, seat, bookingCode
        case cookTime, servings
        case saved
    }

    /// Where the fact was read from.
    public enum Source: Sendable, Equatable {
        /// The text on the receipt.
        case receiptText
        /// The photo's own metadata (EXIF), written by the camera.
        case photoMetadata
        /// The photo's GPS coordinates, named by Apple Maps.
        case photoLocation
        /// The document's own information (its PDF properties).
        case documentInfo
        /// The page's own data (schema.org and meta tags).
        case page
        case walletPass
        case calendarFile
        /// The barcode on a boarding pass.
        case barcode
        /// Laterwise's text rules.
        case textRules
        case model
        /// The price the page showed, picked out of its layout.
        case shownOnPage
        /// Entered or confirmed by the person.
        case user
        /// Laterwise, when it was saved.
        case capture(CaptureSurface)
    }

    public enum Value: Sendable, Equatable {
        case text(String)
        case date(Date, hasTime: Bool)
    }

    public var label: Label
    public var value: Value
    public var source: Source

    public var id: Label { label }

    public init(_ label: Label, _ value: Value, source: Source) {
        self.label = label
        self.value = value
        self.source = source
    }
}

extension ItemRecord {
    /// What the item itself says, by what it is: a receipt's merchant, total and date;
    /// a photo's time and place; a document's author; a page's own data. Ends with
    /// when and how it was saved. Facts inferred from text are in `dates` and `places`.
    public var facts: [ItemFact] {
        let fields = typedFields
        var facts: [ItemFact] = []
        func add(_ label: ItemFact.Label, _ text: String?, _ source: ItemFact.Source) {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            facts.append(ItemFact(label, .text(text), source: source))
        }
        func add(_ label: ItemFact.Label, _ date: Date?, hasTime: Bool, _ source: ItemFact.Source) {
            guard let date else { return }
            facts.append(ItemFact(label, .date(date, hasTime: hasTime), source: source))
        }

        if let receipt = fields?.receipt {
            let source: ItemFact.Source = receipt.origin == .user ? .user : .receiptText
            add(.merchant, receipt.merchant, source)
            add(.total, receipt.total.map { Self.money($0, currency: receipt.currency) }, source)
            add(.purchased, receipt.purchasedAt, hasTime: receipt.purchasedAt.map { FactMerge.hasTimeOfDay($0) } ?? false, source)
        }
        if let photo = fields?.photo {
            add(.taken, photo.takenAt, hasTime: true, .photoMetadata)
            add(.location, photo.placeName, .photoLocation)
        }
        if let article = fields?.article {
            let source: ItemFact.Source = kind == .link ? .page : .documentInfo
            add(.author, article.author, source)
            add(.publisher, article.publisher, source)
            // A PDF's date is when the file was made, not when it was published.
            add(kind == .link ? .published : .created, article.publishedAt, hasTime: false, source)
        }
        if let ticket = fields?.ticket {
            let source = Self.source(ticket.origin)
            add(.starts, ticket.startDate, hasTime: ticket.startHasTime, source)
            add(.doors, ticket.doorsAt, hasTime: true, source)
            add(.ends, ticket.endDate, hasTime: true, source)
            add(.venue, ticket.venue, source)
            add(.address, ticket.address, source)
            add(.seat, ticket.seat, source)
            add(.bookingCode, ticket.bookingCode, source)
        }
        if let trip = fields?.trip {
            // Each leg has its own section; the booking is the trip's.
            add(.bookingCode, trip.bookingCode, Self.source(trip.origin))
        }
        if let product = fields?.product {
            let source = Self.source(product.origin)
            add(.price, product.price.map { Self.money($0, currency: product.currency) }, source)
            if product.changeSinceSaved != nil {
                add(.priceWhenSaved, product.originalPrice.map { Self.money($0, currency: product.currency) }, source)
            }
            if let lowest = product.lowestPrice, lowest != product.price {
                add(.lowestPrice, Self.money(lowest, currency: product.currency), source)
            }
            add(.priceChecked, product.checkedAt, hasTime: true, source)
            add(.store, product.store ?? siteName, source)
            add(.brand, product.brand, source)
            add(.availability, product.availability.map(Self.availability), source)
        }
        if let event = fields?.event {
            add(.starts, event.startDate, hasTime: event.startDate.map { FactMerge.hasTimeOfDay($0) } ?? false, .page)
            add(.ends, event.endDate, hasTime: event.endDate.map { FactMerge.hasTimeOfDay($0) } ?? false, .page)
            add(.venue, event.venue, .page)
            add(.address, event.address, .page)
        }
        if let place = fields?.place {
            add(.address, place.address, .page)
            add(.phone, place.telephone, .page)
        }
        if let recipe = fields?.recipe {
            add(.cookTime, recipe.totalMinutes.map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) }, .page)
            add(.servings, recipe.servings, .page)
        }
        add(.saved, createdAt, hasTime: true, .capture(surface))

        // One row per label: the first (most specific) source wins.
        var seen = Set<String>()
        return facts.filter { seen.insert($0.label.rawValue).inserted }
    }

    /// Facts found in the text (by the date detector or the model), less those
    /// the item's own data already states.
    /// Dates whose meaning isn't known ("mentioned") are left out: "Oct 21 – Oct 26"
    /// alone says nothing about what happens then.
    public var inferredDates: [ItemDate] {
        dates.filter { $0.source != .structured && $0.role != .mentioned }
    }

    /// The words around `evidence` in the item's text, so a date found there reads
    /// with its meaning: "…apply by Oct 26 to join…".
    public func context(of evidence: String, radius: Int = 36) -> String? {
        let needle = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        for source in [text, contentText, ocrText].compactMap({ $0 }) {
            guard let range = source.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            var start = source.index(range.lowerBound, offsetBy: -radius, limitedBy: source.startIndex) ?? source.startIndex
            var end = source.index(range.upperBound, offsetBy: radius, limitedBy: source.endIndex) ?? source.endIndex
            // Whole words: out to the spaces around them (a little further at most).
            for _ in 0..<20 where start > source.startIndex && !source[source.index(before: start)].isWhitespace {
                start = source.index(before: start)
            }
            for _ in 0..<20 where end < source.endIndex && !source[end].isWhitespace {
                end = source.index(after: end)
            }
            let snippet = source[start..<end]
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return (start > source.startIndex ? "…" : "") + snippet + (end < source.endIndex ? "…" : "")
        }
        return nil
    }

    public var inferredPlaces: [ItemPlace] {
        let known = Set(facts.compactMap { fact -> String? in
            if case .text(let text) = fact.value, [.location, .venue, .address].contains(fact.label) { return text.lowercased() }
            return nil
        })
        return places.filter { $0.source != .structured && !known.contains($0.name.lowercased()) }
    }

    public static func source(_ origin: FieldOrigin?) -> ItemFact.Source {
        switch origin {
        case .walletPass: .walletPass
        case .calendarFile: .calendarFile
        case .barcode: .barcode
        case .text: .textRules
        case .document: .documentInfo
        case .model: .model
        case .shown: .shownOnPage
        case .user: .user
        case .page, nil: .page
        }
    }

    /// "https://schema.org/InStock" → "In stock".
    static func availability(_ value: String) -> String {
        let name = value.split(separator: "/").last.map(String.init) ?? value
        switch name.lowercased() {
        case "instock": return String(localized: "In stock")
        case "outofstock", "soldout": return String(localized: "Out of stock")
        case "preorder", "presale": return String(localized: "Pre-order")
        case "limitedavailability": return String(localized: "Limited")
        default: return name
        }
    }
}
