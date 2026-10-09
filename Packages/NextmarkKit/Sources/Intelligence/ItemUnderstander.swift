import Foundation
import Model

/// What the Understand stage knows about an item. Built by the pipeline from
/// source facts and extracted text; never includes user-edited fields except the note.
public struct UnderstandingInput: Sendable, Equatable {
    /// Keeps prompts well inside the 8,192-token on-device context (Docs/architecture.md §6.2).
    public static let maxContentCharacters = 6_000
    public static let maxOCRCharacters = 2_000

    public var title: String?
    public var text: String?
    public var url: URL?
    public var note: String?
    public var ocrText: String?
    /// Coarse Vision labels for images ("food", "document", …).
    public var imageLabels: [String]

    public init(
        title: String? = nil, text: String? = nil, url: URL? = nil, note: String? = nil,
        ocrText: String? = nil, imageLabels: [String] = []
    ) {
        self.title = title
        self.text = text
        self.url = url
        self.note = note
        self.ocrText = ocrText
        self.imageLabels = imageLabels
    }

    public var promptText: String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append("Title: \(title)") }
        if let url { parts.append("URL: \(url.absoluteString)") }
        if let note, !note.isEmpty { parts.append("The person's note: \(note)") }
        if let text, !text.isEmpty { parts.append("Content:\n\(text.prefix(Self.maxContentCharacters))") }
        if let ocrText, !ocrText.isEmpty { parts.append("Text in the image:\n\(ocrText.prefix(Self.maxOCRCharacters))") }
        if !imageLabels.isEmpty { parts.append("The image shows: \(imageLabels.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }
}

public protocol ItemUnderstander: Sendable {
    func understand(_ input: UnderstandingInput) async throws -> Understanding
}

/// Tries `primary`, falls back on any error (model not ready, guardrails, context overflow).
public struct FallbackUnderstander: ItemUnderstander {
    let primary: any ItemUnderstander
    let fallback: any ItemUnderstander

    public init(primary: any ItemUnderstander, fallback: any ItemUnderstander) {
        self.primary = primary
        self.fallback = fallback
    }

    public func understand(_ input: UnderstandingInput) async throws -> Understanding {
        do {
            return try await primary.understand(input)
        } catch {
            return try await fallback.understand(input)
        }
    }
}

public enum IntelligenceRouter {
    /// The best understander this device can run right now.
    public static func makeUnderstander() -> any ItemUnderstander {
        #if canImport(FoundationModels)
        if IntelligenceStatus.current == .available {
            return FallbackUnderstander(primary: FoundationModelsUnderstander(), fallback: HeuristicUnderstander())
        }
        #endif
        return HeuristicUnderstander()
    }
}
