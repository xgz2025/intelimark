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
import Model

/// Suggests next steps for an item from why it was saved and what it is
/// (PRD A2): buy → "Buy … before the sale ends", event → "Go to …", recipe →
/// "Cook …". Deterministic and grounded: due dates come only from the item's own
/// dates. The user confirms a suggestion with one tap.
public enum ActionSuggester {
    static let maximumTitleLength = 60

    public static func suggestions(for item: ItemDigest, now: Date = Date()) -> [SuggestedAction] {
        let title = shortTitle(item.title)
        let upcoming = item.dates.filter { $0.date > now }.sorted { $0.date < $1.date }
        let deadline = upcoming.first { $0.role == .deadline || $0.role == .expiry }
        let event = upcoming.first { $0.role == .eventStart }
        let reservation = upcoming.first { $0.role == .reservation }

        var suggestions: [SuggestedAction] = []
        func add(_ title: String, dueAt: Date? = nil) {
            guard !suggestions.contains(where: { $0.title == title }) else { return }
            suggestions.append(SuggestedAction(title: title, dueAt: dueAt, itemID: item.id))
        }

        if let reservation {
            add(String(localized: "Reservation: \(title)"), dueAt: reservation.date)
        }
        if item.kind == .event || item.kind == .ticket, let event {
            add(String(localized: "Go to \(title)"), dueAt: event.date)
        }
        switch item.intent {
        case .buy:
            add(String(localized: "Buy \(title)"), dueAt: deadline?.date)
        case .read:
            add(String(localized: "Read \(title)"))
        case .tryIt:
            add(item.kind == .recipe ? String(localized: "Cook \(title)") : String(localized: "Try \(title)"), dueAt: deadline?.date)
        case .go:
            if event == nil { add(String(localized: "Visit \(title)"), dueAt: deadline?.date) }
        case .decide:
            add(String(localized: "Decide on \(title)"), dueAt: deadline?.date)
        case .forSomeone:
            add(String(localized: "Share \(title)"))
        case .reference, nil:
            if let deadline { add(String(localized: "Before \(deadline.date.formatted(date: .abbreviated, time: .omitted)): \(title)"), dueAt: deadline.date) }
        }
        return Array(suggestions.prefix(2))
    }

    static func shortTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumTitleLength else { return trimmed }
        let cut = trimmed.prefix(maximumTitleLength)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

/// Names a set of items by what they share: the keyword (or title word) most of
/// them have, e.g. "Kyoto". Used for suggested groups and heuristic briefs.
public enum TopicNamer {
    static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "your", "you", "are", "was", "how", "what", "why",
        "best", "new", "guide", "list", "review", "page", "home", "about", "into", "more", "most", "can", "will",
        "der", "die", "das", "und", "les", "des", "une", "con", "por", "para",
    ]

    /// A topic shared by at least `minimumShare` of the items (and at least two), or nil.
    public static func topic(of items: [ItemDigest], minimumShare: Double = 0.4) -> String? {
        guard items.count >= 2 else { return items.first.map { ActionSuggester.shortTitle($0.title) } }
        let needed = max(2, Int((Double(items.count) * minimumShare).rounded(.up)))
        if let keyword = mostShared(items.map { Set($0.keywords.map(normalize)) }, needed: needed) {
            return display(keyword, in: items.flatMap(\.keywords))
        }
        let titleWords = items.map { item in
            Set(item.title.components(separatedBy: CharacterSet.alphanumerics.inverted).map(normalize))
        }
        if let word = mostShared(titleWords, needed: needed) {
            return display(word, in: items.flatMap { $0.title.components(separatedBy: CharacterSet.alphanumerics.inverted) })
        }
        return nil
    }

    static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The term in the most sets (ties: the longer, then alphabetical), if in at least `needed`.
    static func mostShared(_ sets: [Set<String>], needed: Int) -> String? {
        var counts: [String: Int] = [:]
        for set in sets {
            for term in set where isMeaningful(term) { counts[term, default: 0] += 1 }
        }
        let best = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            if lhs.key.count != rhs.key.count { return lhs.key.count < rhs.key.count }
            return lhs.key > rhs.key
        }
        guard let best, best.value >= needed else { return nil }
        return best.key
    }

    static func isMeaningful(_ term: String) -> Bool {
        guard !term.isEmpty, !stopwords.contains(term), Double(term) == nil else { return false }
        // CJK terms carry meaning in fewer characters.
        let isCJK = term.unicodeScalars.contains { (0x3040...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
        return isCJK || term.count >= 3
    }

    /// The term as most often written ("Kyoto", not "kyoto").
    static func display(_ term: String, in originals: [String]) -> String {
        let spellings = originals.filter { normalize($0) == term }
        var counts: [String: Int] = [:]
        for spelling in spellings { counts[spelling.trimmingCharacters(in: .whitespacesAndNewlines), default: 0] += 1 }
        let best = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? term
        return best.prefix(1).uppercased() + best.dropFirst()
    }
}
