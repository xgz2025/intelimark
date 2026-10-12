//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

#if canImport(FoundationModels)
import Foundation
import FoundationModels
import Model

/// On-device understanding with Apple's Foundation Models framework and guided
/// generation (Docs/architecture.md §6.2). One short session per item; dates and
/// places are kept only when the source text supports them.
public struct FoundationModelsUnderstander: ItemUnderstander {
    static let instructions = """
        You describe things a person saved for later: web pages, screenshots, photos, notes and documents.
        Be specific and factual. Use only the information given. Never invent dates, places, prices or names.
        Write in the language of the content.
        """
    /// Budget scale for the single retry after a context overflow.
    static let retryBudgetScale = 0.4

    /// Room for the title, summary, keywords, dates and places, with margin.
    static let maximumResponseTokens = 1_000

    public init() {}

    public func understand(_ input: UnderstandingInput) async throws -> Understanding {
        do {
            return try await ModelCall.run(within: ModelTimeLimit.understanding) {
                try await generate(input, budgetScale: 1)
            }
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            return try await ModelCall.run(within: ModelTimeLimit.understanding) {
                try await generate(input, budgetScale: Self.retryBudgetScale)
            }
        }
    }

    private func generate(_ input: UnderstandingInput, budgetScale: Double) async throws -> Understanding {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: input.promptText(budgetScale: budgetScale),
            generating: GeneratedUnderstanding.self,
            options: GenerationOptions(maximumResponseTokens: Self.maximumResponseTokens)
        )
        let generated = response.content
        let source = input.groundingText
        let description = generated.imageDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return Understanding(
            title: generated.title,
            summary: generated.summary,
            semanticKind: generated.kind.semanticKind,
            likelyIntent: generated.likelyIntent.intent,
            keywords: generated.keywords,
            imageDescription: input.isImage && !description.isEmpty ? description : nil,
            dates: Grounding.dates(
                from: generated.dates.map { DateCandidate(evidence: $0.evidence, isoDate: $0.isoDate, role: $0.role.role) },
                in: source
            ),
            places: Grounding.places(
                from: generated.places.map { PlaceCandidate(name: $0.name, address: $0.address) },
                in: source
            ),
            producer: "foundation-models",
            isProvisional: false
        )
    }
}

/// One call to the on-device model, with a time limit. What's worth trying again
/// later (busy, rate-limited, still downloading, too slow) comes out as `ModelBusy`;
/// anything else (a guardrail, an unsupported language) is passed on as it is.
enum ModelCall {
    static func run<T: Sendable>(
        within seconds: TimeInterval,
        _ call: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await withTimeLimit(seconds, operation: call)
        } catch is TimeLimitExceeded {
            throw ModelBusy()
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests, .assetsUnavailable:
                throw ModelBusy()
            default:
                throw error
            }
        }
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

    @Guide(description: "Only for a photo or screenshot: one sentence describing what it shows, including any important text. Empty for other items.")
    var imageDescription: String

    @Guide(description: "Dates stated in the content that matter to the person: event times, deadlines, expiry dates, bookings. Leave empty if none are stated.", .maximumCount(5))
    var dates: [GeneratedDate]

    @Guide(description: "Specific named places in the content: venues, restaurants, shops, hotels, addresses. Leave empty if none.", .maximumCount(5))
    var places: [GeneratedPlace]
}

@Generable
struct GeneratedDate {
    @Guide(description: "The exact words copied from the content that state this date")
    var evidence: String

    @Guide(description: "The date as yyyy-MM-dd, or yyyy-MM-ddTHH:mm when a time is stated. Use the saved-on date to resolve the year.")
    var isoDate: String

    var role: GeneratedDateRole
}

@Generable
enum GeneratedDateRole {
    case eventStart, eventEnd, deadline, expiry, reservation, mentioned

    var role: ItemDate.Role {
        switch self {
        case .eventStart: .eventStart
        case .eventEnd: .eventEnd
        case .deadline: .deadline
        case .expiry: .expiry
        case .reservation: .reservation
        case .mentioned: .mentioned
        }
    }
}

@Generable
struct GeneratedPlace {
    @Guide(description: "The place's name exactly as written in the content")
    var name: String

    @Guide(description: "The street address if the content states one, otherwise empty")
    var address: String
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
