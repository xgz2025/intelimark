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

/// Facts taken from schema.org data (or, later, the model) for kinds that support
/// Compare and Moments (PRD U4). Every field is optional: pages are inconsistent.
public struct TypedFields: Codable, Sendable, Hashable {
    public var product: ProductFields?
    public var place: PlaceFields?
    public var event: EventFields?
    public var recipe: RecipeFields?
    public var article: ArticleFields?
    /// Read from a receipt's text (a photo or screenshot of one).
    public var receipt: ReceiptFields?
    /// A photo's own metadata: when and where it was taken.
    public var photo: PhotoFields?
    /// A ticket for a show, concert, game or film (Docs/save_types.md).
    public var ticket: TicketFields?
    /// A flight, train, bus or boat ticket, boarding pass or itinerary.
    public var trip: TripFields?
    /// What the person said this isn't ("Not a Receipt"): `SaveType` raw values. Kept
    /// when the item is read again, so the same guess isn't made twice.
    public var rejected: [String]?

    public init(
        product: ProductFields? = nil,
        place: PlaceFields? = nil,
        event: EventFields? = nil,
        recipe: RecipeFields? = nil,
        article: ArticleFields? = nil,
        receipt: ReceiptFields? = nil,
        photo: PhotoFields? = nil,
        ticket: TicketFields? = nil,
        trip: TripFields? = nil,
        rejected: [String]? = nil
    ) {
        self.product = product
        self.place = place
        self.event = event
        self.recipe = recipe
        self.article = article
        self.receipt = receipt
        self.photo = photo
        self.ticket = ticket
        self.trip = trip
        self.rejected = rejected
    }

    /// `other`'s fields where these have none: exact sources first, then the rest.
    public func filling(from other: TypedFields?) -> TypedFields {
        guard let other else { return self }
        var merged = self
        merged.product = product ?? other.product
        merged.place = place ?? other.place
        merged.event = event ?? other.event
        merged.recipe = recipe ?? other.recipe
        merged.article = article ?? other.article
        merged.receipt = receipt ?? other.receipt
        merged.photo = photo ?? other.photo
        merged.ticket = ticket ?? other.ticket
        merged.trip = trip ?? other.trip
        merged.rejected = rejected ?? other.rejected
        return merged
    }
}

/// Where a typed field was read from, shown under it on the item's screen.
public enum FieldOrigin: String, Codable, Sendable, Hashable {
    /// The page's own data (schema.org, Open Graph and product tags).
    case page
    /// A Wallet pass.
    case walletPass
    /// A calendar file.
    case calendarFile
    /// The barcode on a boarding pass.
    case barcode
    /// Laterwise's text rules, on the item's text or the text in its picture.
    case text
    /// The document's own properties.
    case document
    /// The on-device model.
    case model
    /// The price a page shows to a person, picked out of its layout: likely, not certain.
    case shown
    /// Entered or confirmed by the person ("Correct?").
    case user

    /// Read by rules or a model rather than stated by the item: worth a "Correct?".
    public var isUncertain: Bool {
        switch self {
        case .text, .model, .shown: true
        case .page, .walletPass, .calendarFile, .barcode, .document, .user: false
        }
    }
}

/// A ticket for a show, concert, game, film or exhibition.
public struct TicketFields: Codable, Sendable, Hashable {
    public var name: String?
    public var startDate: Date?
    /// False when only the day is known.
    public var startHasTime: Bool
    public var doorsAt: Date?
    public var endDate: Date?
    public var venue: String?
    public var address: String?
    public var seat: String?
    public var bookingCode: String?
    public var origin: FieldOrigin?

    public init(
        name: String? = nil, startDate: Date? = nil, startHasTime: Bool = true, doorsAt: Date? = nil,
        endDate: Date? = nil, venue: String? = nil, address: String? = nil, seat: String? = nil,
        bookingCode: String? = nil, origin: FieldOrigin? = nil
    ) {
        self.name = name
        self.startDate = startDate
        self.startHasTime = startHasTime
        self.doorsAt = doorsAt
        self.endDate = endDate
        self.venue = venue
        self.address = address
        self.seat = seat
        self.bookingCode = bookingCode
        self.origin = origin
    }
}

/// A journey: one or more legs by plane, train, bus or boat.
public struct TripFields: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable, Hashable, CaseIterable {
        case flight, train, bus, boat, other
    }

    public var mode: Mode
    public var legs: [TripLeg]
    /// The booking reference (PNR, order number).
    public var bookingCode: String?
    public var origin: FieldOrigin?

    public init(mode: Mode, legs: [TripLeg], bookingCode: String? = nil, origin: FieldOrigin? = nil) {
        self.mode = mode
        self.legs = legs
        self.bookingCode = bookingCode
        self.origin = origin
    }

    /// The first leg still ahead at `now` (or about to leave), else the last one.
    public func currentLeg(now: Date = Date()) -> TripLeg? {
        legs.first { leg in
            guard let departure = leg.departure else { return false }
            return (leg.arrival ?? departure.addingTimeInterval(3600)) > now
        } ?? legs.last
    }

    /// When the whole trip is over: the last arrival, or the last departure.
    public var end: Date? {
        legs.compactMap { $0.arrival ?? $0.departure }.max()
    }
}

public struct TripLeg: Codable, Sendable, Hashable {
    /// The airline, railway or operator ("China Eastern", "JR East").
    public var carrier: String?
    /// "MU 523", "G1234".
    public var number: String?
    /// Where it leaves from: a city, airport or station name.
    public var from: String?
    /// An airport's IATA code ("PVG"), when known.
    public var fromCode: String?
    public var to: String?
    public var toCode: String?
    public var departure: Date?
    /// False when only the day is known (a boarding pass barcode, say).
    public var departureHasTime: Bool
    public var arrival: Date?
    public var terminal: String?
    public var gate: String?
    public var platform: String?
    public var seat: String?

    public init(
        carrier: String? = nil, number: String? = nil, from: String? = nil, fromCode: String? = nil,
        to: String? = nil, toCode: String? = nil, departure: Date? = nil, departureHasTime: Bool = true,
        arrival: Date? = nil, terminal: String? = nil, gate: String? = nil, platform: String? = nil, seat: String? = nil
    ) {
        self.carrier = carrier
        self.number = number
        self.from = from
        self.fromCode = fromCode
        self.to = to
        self.toCode = toCode
        self.departure = departure
        self.departureHasTime = departureHasTime
        self.arrival = arrival
        self.terminal = terminal
        self.gate = gate
        self.platform = platform
        self.seat = seat
    }

    /// "Shanghai (PVG)", "PVG" or "Shanghai Hongqiao".
    public var fromLabel: String? { Self.label(from, fromCode) }
    public var toLabel: String? { Self.label(to, toCode) }

    static func label(_ name: String?, _ code: String?) -> String? {
        switch (name, code) {
        case let (name?, code?) where name.caseInsensitiveCompare(code) != .orderedSame: "\(name) (\(code))"
        case let (name?, _): name
        case let (nil, code?): code
        default: nil
        }
    }
}

/// A price seen at a moment: the price history of a product.
public struct PricePoint: Codable, Sendable, Hashable {
    public var at: Date
    public var price: Double

    public init(at: Date, price: Double) {
        self.at = at
        self.price = price
    }
}

public struct ReceiptFields: Codable, Sendable, Hashable {
    public var merchant: String?
    public var total: Double?
    /// ISO 4217 code when the receipt makes it clear ("USD", "EUR"…).
    public var currency: String?
    /// The date printed on the receipt.
    public var purchasedAt: Date?
    /// Text rules or the model, unless the person corrected it.
    public var origin: FieldOrigin?

    public init(merchant: String? = nil, total: Double? = nil, currency: String? = nil, purchasedAt: Date? = nil, origin: FieldOrigin? = nil) {
        self.merchant = merchant
        self.total = total
        self.currency = currency
        self.purchasedAt = purchasedAt
        self.origin = origin
    }
}

public struct PhotoFields: Codable, Sendable, Hashable {
    public var takenAt: Date?
    public var latitude: Double?
    public var longitude: Double?
    /// "Shibuya, Tokyo": named from the coordinates, when that was possible.
    public var placeName: String?

    public init(takenAt: Date? = nil, latitude: Double? = nil, longitude: Double? = nil, placeName: String? = nil) {
        self.takenAt = takenAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }
}

public struct ProductFields: Codable, Sendable, Hashable {
    public var name: String?
    public var brand: String?
    /// The latest price seen.
    public var price: Double?
    public var currency: String?
    public var availability: String?
    public var description: String?
    public var imageURL: String?
    /// The shop ("Amazon", "Shein").
    public var store: String?
    /// The first price seen, when it was saved: "↓ $50 since saved".
    public var originalPrice: Double?
    /// Prices seen by Check Price, oldest first, at most `maxHistory`.
    public var priceHistory: [PricePoint]?
    /// When the price was last checked.
    public var checkedAt: Date?
    public var origin: FieldOrigin?

    public static let maxHistory = 60

    public init(
        name: String? = nil, brand: String? = nil, price: Double? = nil, currency: String? = nil,
        availability: String? = nil, description: String? = nil, imageURL: String? = nil, store: String? = nil,
        originalPrice: Double? = nil, priceHistory: [PricePoint]? = nil, checkedAt: Date? = nil, origin: FieldOrigin? = nil
    ) {
        self.name = name
        self.brand = brand
        self.price = price
        self.currency = currency
        self.availability = availability
        self.description = description
        self.imageURL = imageURL
        self.store = store
        self.originalPrice = originalPrice
        self.priceHistory = priceHistory
        self.checkedAt = checkedAt
        self.origin = origin
    }

    /// The price change since it was saved, when there is one.
    public var changeSinceSaved: Double? {
        guard let price, let originalPrice, abs(price - originalPrice) >= 0.005 else { return nil }
        return price - originalPrice
    }

    /// Records a price seen at `date`: the latest price, the first one kept as the
    /// original, and the history (a point per change, or per day at most).
    public mutating func record(price newPrice: Double, currency newCurrency: String?, at date: Date) {
        var history = priceHistory ?? []
        if let newCurrency, let currency, newCurrency != currency {
            // Another currency (another region's page): start over rather than compare them.
            originalPrice = nil
            price = nil
            history = []
        }
        if history.isEmpty, let price {
            history.append(PricePoint(at: checkedAt ?? date, price: price))
        }
        if originalPrice == nil { originalPrice = price ?? newPrice }
        // Unchanged within a day: nothing new to keep.
        let unchanged = history.last.map { $0.price == newPrice && date.timeIntervalSince($0.at) < 86_400 } ?? false
        if !unchanged {
            history.append(PricePoint(at: date, price: newPrice))
        }
        priceHistory = Array(history.suffix(Self.maxHistory))
        price = newPrice
        currency = newCurrency ?? currency
        checkedAt = date
    }

    /// The lowest price seen.
    public var lowestPrice: Double? {
        ([price, originalPrice].compactMap { $0 } + (priceHistory ?? []).map(\.price)).min()
    }
}

public struct PlaceFields: Codable, Sendable, Hashable {
    public var name: String?
    public var address: String?
    public var latitude: Double?
    public var longitude: Double?
    public var telephone: String?

    public init(name: String? = nil, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil, telephone: String? = nil) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.telephone = telephone
    }
}

public struct EventFields: Codable, Sendable, Hashable {
    public var name: String?
    public var startDate: Date?
    public var endDate: Date?
    public var venue: String?
    public var address: String?

    public init(name: String? = nil, startDate: Date? = nil, endDate: Date? = nil, venue: String? = nil, address: String? = nil) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.venue = venue
        self.address = address
    }
}

public struct RecipeFields: Codable, Sendable, Hashable {
    public var name: String?
    public var ingredients: [String]
    public var totalMinutes: Int?
    public var servings: String?

    public init(name: String? = nil, ingredients: [String] = [], totalMinutes: Int? = nil, servings: String? = nil) {
        self.name = name
        self.ingredients = ingredients
        self.totalMinutes = totalMinutes
        self.servings = servings
    }
}

public struct ArticleFields: Codable, Sendable, Hashable {
    public var headline: String?
    public var author: String?
    public var publisher: String?
    public var publishedAt: Date?

    public init(headline: String? = nil, author: String? = nil, publisher: String? = nil, publishedAt: Date? = nil) {
        self.headline = headline
        self.author = author
        self.publisher = publisher
        self.publishedAt = publishedAt
    }
}

/// The kind and fields a page declares about itself in schema.org JSON-LD.
public struct StructuredData: Sendable, Hashable {
    public var kind: SemanticKind
    public var fields: TypedFields

    public init(kind: SemanticKind, fields: TypedFields) {
        self.kind = kind
        self.fields = fields
    }
}

/// The result of the Extract stage (PRD U1). Facts only: no model output.
public struct Extraction: Sendable, Hashable {
    public var title: String?
    public var siteName: String?
    public var language: String?
    public var canonicalURL: URL?
    public var heroImageURL: URL?
    /// Readable article text, PDF text, or the page description as a fallback.
    public var contentText: String?
    public var ocrText: String?
    public var imageLabels: [String]
    public var barcodes: [String]
    public var structured: StructuredData?
    /// Facts about a file that don't say what kind of thing it is: a photo's time and
    /// place, a document's title and author. Kept in `typedFields` alongside `structured`.
    public var fileFields: TypedFields?

    public init(
        title: String? = nil,
        siteName: String? = nil,
        language: String? = nil,
        canonicalURL: URL? = nil,
        heroImageURL: URL? = nil,
        contentText: String? = nil,
        ocrText: String? = nil,
        imageLabels: [String] = [],
        barcodes: [String] = [],
        structured: StructuredData? = nil,
        fileFields: TypedFields? = nil
    ) {
        self.title = title
        self.siteName = siteName
        self.language = language
        self.canonicalURL = canonicalURL
        self.heroImageURL = heroImageURL
        self.contentText = contentText
        self.ocrText = ocrText
        self.imageLabels = imageLabels
        self.barcodes = barcodes
        self.structured = structured
        self.fileFields = fileFields
    }

    /// What goes in the item's `typedFields`: the declared fields, with the file's own added.
    public var typedFields: TypedFields? {
        guard let fields = structured?.fields ?? fileFields else { return nil }
        return fields.filling(from: fileFields)
    }
}
