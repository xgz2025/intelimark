import Foundation
import Model

/// The no-model fallback (Docs/architecture.md §5.3): good enough titles, kinds and
/// keywords from URLs and text alone. Deterministic, so it is also the test double.
public struct HeuristicUnderstander: ItemUnderstander {
    public init() {}

    /// Dates further out than this are more likely noise (copyright years, archives).
    static let dateHorizon: TimeInterval = 2 * 365 * 24 * 60 * 60
    static let maxDates = 3

    public func understand(_ input: UnderstandingInput) async throws -> Understanding {
        Understanding(
            title: Self.title(for: input),
            summary: Self.summary(for: input),
            semanticKind: Self.kind(for: input),
            likelyIntent: nil,
            keywords: Self.keywords(for: input),
            imageDescription: Self.imageDescription(for: input),
            dates: Self.dates(for: input),
            producer: "heuristic",
            isProvisional: true
        )
    }

    /// Upcoming dates found by `NSDataDetector`. Without a model there is no way to
    /// tell a deadline from a mention, so every date is `.mentioned`.
    static func dates(for input: UnderstandingInput) -> [ItemDate] {
        let reference = input.capturedAt ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: reference)
        var dates: [ItemDate] = []
        for match in DateFinder.matches(in: input.groundingText) {
            guard match.mentionsDay, match.date >= startOfDay, match.date.timeIntervalSince(reference) <= dateHorizon,
                  !dates.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: match.date) })
            else { continue }
            dates.append(ItemDate(date: match.date, hasTime: match.hasTime, role: .mentioned, evidence: match.text, source: .detector))
            if dates.count == maxDates { break }
        }
        return dates
    }

    /// "food, plate — “Lunch special 980 yen”": labels plus the first line of text,
    /// so photos are findable by what they show until the model can describe them.
    static func imageDescription(for input: UnderstandingInput) -> String? {
        guard input.isImage else { return nil }
        var parts: [String] = []
        if !input.imageLabels.isEmpty { parts.append(input.imageLabels.prefix(4).joined(separator: ", ")) }
        let firstLine = input.ocrText?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let firstLine { parts.append("“\(firstLine.prefix(60))”") }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    static func title(for input: UnderstandingInput) -> String {
        if let title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return String(title.prefix(80))
        }
        let firstLine = input.text?
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let firstLine, !firstLine.isEmpty { return String(firstLine.prefix(80)) }
        if let host = input.url?.host() { return host }
        return String(localized: "Untitled")
    }

    static func summary(for input: UnderstandingInput) -> String {
        guard let text = (input.text ?? input.ocrText)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return "" }
        guard text.count > 240 else { return text }
        let cut = text.prefix(240)
        let boundary = cut.lastIndex(where: \.isWhitespace) ?? cut.endIndex
        return String(cut[..<boundary]) + "…"
    }

    static func kind(for input: UnderstandingInput) -> SemanticKind {
        if let url = input.url {
            let host = url.host()?.lowercased() ?? ""
            let path = url.path().lowercased()
            if host.contains("youtube.") || host.contains("youtu.be") || host.contains("vimeo.") { return .video }
            if host.contains("maps.apple") || host.contains("maps.google") || (host.contains("google.") && path.hasPrefix("/maps")) {
                return .place
            }
            if ["amazon.", "ebay.", "etsy.", "aliexpress."].contains(where: { host.contains($0) }) { return .product }
            if ["eventbrite.", "ticketmaster.", "meetup."].contains(where: { host.contains($0) }) { return .event }
            if url.pathExtension.lowercased() == "pdf" { return .document }
            return .article
        }
        if let text = input.text, !text.isEmpty { return text.count <= 280 ? .quote : .document }
        return .other
    }

    static let stopwords: Set<String> = [
        "about", "after", "also", "been", "being", "from", "have", "into", "just", "more", "most",
        "only", "other", "over", "some", "such", "than", "that", "their", "them", "then", "there",
        "these", "they", "this", "very", "were", "what", "when", "where", "which", "while", "will",
        "with", "would", "your", "https", "http", "www",
    ]

    static func keywords(for input: UnderstandingInput, limit: Int = 8) -> [String] {
        let source = [input.title, input.text, input.ocrText].compactMap { $0 }.joined(separator: " ").lowercased()
        var counts: [String: Int] = [:]
        var order: [String] = []
        for word in source.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let token = String(word)
            guard token.count >= 4, !stopwords.contains(token) else { continue }
            if counts[token] == nil { order.append(token) }
            counts[token, default: 0] += 1
        }
        let firstSeen = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order
            .sorted { lhs, rhs in
                let (l, r) = (counts[lhs] ?? 0, counts[rhs] ?? 0)
                return l != r ? l > r : (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0)
            }
            .prefix(limit)
            .map { $0 }
    }
}
