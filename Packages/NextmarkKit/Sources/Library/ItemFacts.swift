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
        case price, brand, availability
        case starts, ends, venue, address, phone
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
            add(.merchant, receipt.merchant, .receiptText)
            add(.total, receipt.total.map { Self.money($0, currency: receipt.currency) }, .receiptText)
            add(.purchased, receipt.purchasedAt, hasTime: receipt.purchasedAt.map { FactMerge.hasTimeOfDay($0) } ?? false, .receiptText)
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
        if let product = fields?.product {
            add(.price, product.price.map { Self.money($0, currency: product.currency) }, .page)
            add(.brand, product.brand, .page)
            add(.availability, product.availability.map(Self.availability), .page)
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
    public var inferredDates: [ItemDate] {
        dates.filter { $0.source != .structured }
    }

    public var inferredPlaces: [ItemPlace] {
        let known = Set(facts.compactMap { fact -> String? in
            if case .text(let text) = fact.value, [.location, .venue, .address].contains(fact.label) { return text.lowercased() }
            return nil
        })
        return places.filter { $0.source != .structured && !known.contains($0.name.lowercased()) }
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
