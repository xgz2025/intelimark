#if canImport(FoundationModels)
import Foundation
import FoundationModels
import Model

/// On-device understanding with Apple's Foundation Models framework and guided
/// generation (Docs/architecture.md §6.2). One short session per item.
public struct FoundationModelsUnderstander: ItemUnderstander {
    static let instructions = """
        You label things a person saved for later: web pages, screenshots, notes and documents.
        Be specific and factual. Use only the information given. Write in the language of the content.
        """

    public init() {}

    public func understand(_ input: UnderstandingInput) async throws -> Understanding {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: input.promptText, generating: GeneratedUnderstanding.self)
        let generated = response.content
        return Understanding(
            title: generated.title,
            summary: generated.summary,
            semanticKind: generated.kind.semanticKind,
            likelyIntent: generated.likelyIntent.intent,
            keywords: generated.keywords,
            producer: "foundation-models"
        )
    }
}

@Generable
struct GeneratedUnderstanding {
    @Guide(description: "A short, specific title of at most 8 words")
    var title: String

    @Guide(description: "One or two sentences: what this is and why it might matter to the person")
    var summary: String

    @Guide(description: "What kind of thing this is")
    var kind: GeneratedKind

    @Guide(description: "The most likely reason the person saved it")
    var likelyIntent: GeneratedIntent

    @Guide(description: "Search keywords a person might type to find this again", .maximumCount(8))
    var keywords: [String]
}

@Generable
enum GeneratedKind {
    case article, product, place, event, recipe, video, person, receipt, ticket, quote, document, other

    var semanticKind: SemanticKind {
        switch self {
        case .article: .article
        case .product: .product
        case .place: .place
        case .event: .event
        case .recipe: .recipe
        case .video: .video
        case .person: .person
        case .receipt: .receipt
        case .ticket: .ticket
        case .quote: .quote
        case .document: .document
        case .other: .other
        }
    }
}

@Generable
enum GeneratedIntent {
    case read, buy, tryOut, go, decide, reference, forSomeone

    var intent: Intent {
        switch self {
        case .read: .read
        case .buy: .buy
        case .tryOut: .tryIt
        case .go: .go
        case .decide: .decide
        case .reference: .reference
        case .forSomeone: .forSomeone
        }
    }
}
#endif
