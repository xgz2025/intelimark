import SwiftUI
import Model

extension Intent {
    public var title: LocalizedStringKey {
        switch self {
        case .read: "Read"
        case .buy: "Buy"
        case .tryIt: "Try"
        case .go: "Go"
        case .decide: "Decide"
        case .reference: "Reference"
        case .forSomeone: "For someone"
        }
    }

    public var symbolName: String {
        switch self {
        case .read: "book"
        case .buy: "cart"
        case .tryIt: "sparkles"
        case .go: "mappin.and.ellipse"
        case .decide: "arrow.triangle.branch"
        case .reference: "bookmark"
        case .forSomeone: "gift"
        }
    }

    public var tint: Color {
        switch self {
        case .read: .blue
        case .buy: .green
        case .tryIt: .orange
        case .go: .teal
        case .decide: .purple
        case .reference: .gray
        case .forSomeone: .pink
        }
    }
}

extension ItemKind {
    public var symbolName: String {
        switch self {
        case .link: "link"
        case .image: "photo"
        case .text: "text.quote"
        case .pdf: "doc.richtext"
        case .file: "doc"
        case .email: "envelope"
        case .note: "note.text"
        case .aiSession: "bubble.left.and.text.bubble.right"
        }
    }
}

extension SemanticKind {
    public var title: LocalizedStringKey {
        switch self {
        case .article: "Article"
        case .product: "Product"
        case .place: "Place"
        case .event: "Event"
        case .recipe: "Recipe"
        case .video: "Video"
        case .person: "Person"
        case .receipt: "Receipt"
        case .ticket: "Ticket"
        case .quote: "Quote"
        case .document: "Document"
        case .other: "Other"
        }
    }

    /// For section headers ("Receipts", "Tickets"…).
    public var pluralTitle: LocalizedStringKey {
        switch self {
        case .article: "Articles"
        case .product: "Products"
        case .place: "Places"
        case .event: "Events"
        case .recipe: "Recipes"
        case .video: "Videos"
        case .person: "People"
        case .receipt: "Receipts"
        case .ticket: "Tickets"
        case .quote: "Quotes"
        case .document: "Documents"
        case .other: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .article: "doc.text"
        case .product: "bag"
        case .place: "mappin.and.ellipse"
        case .event: "calendar"
        case .recipe: "fork.knife"
        case .video: "play.rectangle"
        case .person: "person"
        case .receipt: "receipt"
        case .ticket: "ticket"
        case .quote: "quote.opening"
        case .document: "doc"
        case .other: "square.dashed"
        }
    }
}
