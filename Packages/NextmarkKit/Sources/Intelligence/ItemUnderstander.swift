import Foundation
import Model

/// What the Understand stage knows about an item. Built by the pipeline from
/// source facts and extracted text; never includes user-edited fields except the note.
public struct UnderstandingInput: Sendable, Equatable {
    /// Token budgets keep the prompt well inside the 8,192-token on-device context,
    /// leaving room for instructions, the output schema and the answer
    /// (Docs/architecture.md §6.2).
    public static let contentTokenBudget = 2_400
    public static let highlightTokenBudget = 300
    public static let ocrTokenBudget = 600

    public var title: String?
    public var text: String?
    /// The passage the user selected, when the item also has page text.
    public var highlight: String?
    public var url: URL?
    public var note: String?
    public var ocrText: String?
    /// Coarse Vision labels for images ("food", "document", …).
    public var imageLabels: [String]
    public var kind: ItemKind?
    /// When the item was saved: anchors relative and year-less dates.
    public var capturedAt: Date?

    public init(
        title: String? = nil, text: String? = nil, highlight: String? = nil, url: URL? = nil, note: String? = nil,
        ocrText: String? = nil, imageLabels: [String] = [], kind: ItemKind? = nil, capturedAt: Date? = nil
    ) {
        self.title = title
        self.text = text
        self.highlight = highlight
        self.url = url
        self.note = note
        self.ocrText = ocrText
        self.imageLabels = imageLabels
        self.kind = kind
        self.capturedAt = capturedAt
    }

    public var isImage: Bool { kind == .image }

    public var promptText: String { promptText(budgetScale: 1) }

    /// The prompt, with long fields cut to their token budgets × `budgetScale`.
    public func promptText(budgetScale: Double) -> String {
        func budget(_ tokens: Int) -> Int { max(1, Int(Double(tokens) * budgetScale)) }
        var parts: [String] = []
        if let capturedAt { parts.append("Saved on: \(Self.dayFormatter().string(from: capturedAt))") }
        if let kind { parts.append("Item type: \(Self.describe(kind))") }
        if let title, !title.isEmpty { parts.append("Title: \(title)") }
        if let url { parts.append("URL: \(url.absoluteString)") }
        if let note, !note.isEmpty { parts.append("The person's note: \(note)") }
        if let highlight, !highlight.isEmpty {
            parts.append("Passage the person highlighted:\n\(TokenBudget.truncate(highlight, to: budget(Self.highlightTokenBudget)))")
        }
        if let text, !text.isEmpty {
            parts.append("Content:\n\(TokenBudget.truncate(text, to: budget(Self.contentTokenBudget)))")
        }
        if let ocrText, !ocrText.isEmpty {
            parts.append("Text in the image:\n\(TokenBudget.truncate(ocrText, to: budget(Self.ocrTokenBudget)))")
        }
        if !imageLabels.isEmpty { parts.append("The image shows: \(imageLabels.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }

    /// Everything a grounded fact may be quoted from.
    public var groundingText: String {
        [title, highlight, text, ocrText, note].compactMap { $0 }.joined(separator: "\n")
    }

    static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd (EEEE)"
        return formatter
    }

    static func describe(_ kind: ItemKind) -> String {
        switch kind {
        case .link: "web page"
        case .image: "photo or screenshot"
        case .text: "text passage"
        case .pdf: "PDF document"
        case .file: "file"
        case .email: "email"
        case .note: "note"
        case .aiSession: "AI conversation"
        }
    }
}

public protocol ItemUnderstander: Sendable {
    func understand(_ input: UnderstandingInput) async throws -> Understanding
}

/// Uses `primary` (the on-device model) when it is available right now, and
/// `fallback` otherwise or when it fails (guardrails, unsupported language, a
/// context overflow it couldn't recover from). Checked per item, so a model that
/// finishes downloading mid-session is picked up without a relaunch.
public struct AdaptiveUnderstander: ItemUnderstander {
    let primary: any ItemUnderstander
    let fallback: any ItemUnderstander
    let isPrimaryAvailable: @Sendable () -> Bool

    public init(
        primary: any ItemUnderstander,
        fallback: any ItemUnderstander,
        isPrimaryAvailable: @escaping @Sendable () -> Bool
    ) {
        self.primary = primary
        self.fallback = fallback
        self.isPrimaryAvailable = isPrimaryAvailable
    }

    public func understand(_ input: UnderstandingInput) async throws -> Understanding {
        guard isPrimaryAvailable() else { return try await fallback.understand(input) }
        do {
            return try await primary.understand(input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.understand(input)
        }
    }
}

public enum IntelligenceRouter {
    /// The understander for this device: the on-device model when Apple
    /// Intelligence is available, the heuristic otherwise.
    public static func makeUnderstander() -> any ItemUnderstander {
        #if canImport(FoundationModels)
        return AdaptiveUnderstander(
            primary: FoundationModelsUnderstander(),
            fallback: HeuristicUnderstander(),
            isPrimaryAvailable: { IntelligenceStatus.current == .available }
        )
        #else
        return HeuristicUnderstander()
        #endif
    }
}
