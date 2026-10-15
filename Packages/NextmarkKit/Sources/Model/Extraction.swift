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

    public init(
        product: ProductFields? = nil,
        place: PlaceFields? = nil,
        event: EventFields? = nil,
        recipe: RecipeFields? = nil,
        article: ArticleFields? = nil,
        receipt: ReceiptFields? = nil,
        photo: PhotoFields? = nil
    ) {
        self.product = product
        self.place = place
        self.event = event
        self.recipe = recipe
        self.article = article
        self.receipt = receipt
        self.photo = photo
    }
}

public struct ReceiptFields: Codable, Sendable, Hashable {
    public var merchant: String?
    public var total: Double?
    /// ISO 4217 code when the receipt makes it clear ("USD", "EUR"…).
    public var currency: String?
    /// The date printed on the receipt.
    public var purchasedAt: Date?

    public init(merchant: String? = nil, total: Double? = nil, currency: String? = nil, purchasedAt: Date? = nil) {
        self.merchant = merchant
        self.total = total
        self.currency = currency
        self.purchasedAt = purchasedAt
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
    public var price: Double?
    public var currency: String?
    public var availability: String?

    public init(name: String? = nil, brand: String? = nil, price: Double? = nil, currency: String? = nil, availability: String? = nil) {
        self.name = name
        self.brand = brand
        self.price = price
        self.currency = currency
        self.availability = availability
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
        guard var fields = structured?.fields ?? fileFields else { return nil }
        if let fileFields {
            fields.photo = fields.photo ?? fileFields.photo
            fields.article = fields.article ?? fileFields.article
        }
        return fields
    }
}
