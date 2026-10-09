import Foundation

/// Facts taken from schema.org data (or, later, the model) for kinds that support
/// Compare and Moments (PRD U4). Every field is optional: pages are inconsistent.
public struct TypedFields: Codable, Sendable, Hashable {
    public var product: ProductFields?
    public var place: PlaceFields?
    public var event: EventFields?
    public var recipe: RecipeFields?
    public var article: ArticleFields?

    public init(
        product: ProductFields? = nil,
        place: PlaceFields? = nil,
        event: EventFields? = nil,
        recipe: RecipeFields? = nil,
        article: ArticleFields? = nil
    ) {
        self.product = product
        self.place = place
        self.event = event
        self.recipe = recipe
        self.article = article
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
        structured: StructuredData? = nil
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
    }
}
