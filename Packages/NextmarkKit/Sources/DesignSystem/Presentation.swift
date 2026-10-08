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
