import Foundation

/// Deterministic date detection with `NSDataDetector`: the fallback understander's
/// date source, and the check model-proposed dates must pass (Docs/architecture.md §6.2).
public enum DateFinder {
    public struct Match: Sendable, Equatable {
        public var date: Date
        public var hasTime: Bool
        public var text: String
    }

    static let maxScannedCharacters = 20_000

    public static func matches(in text: String) -> [Match] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return [] }
        let scanned = String(text.prefix(maxScannedCharacters))
        return detector.matches(in: scanned, range: NSRange(scanned.startIndex..., in: scanned)).compactMap { result in
            guard let date = result.date, let range = Range(result.range, in: scanned) else { return nil }
            let matched = String(scanned[range])
            return Match(date: date, hasTime: mentionsTimeOfDay(matched), text: matched)
        }
    }

    /// "7:30", "7pm", "19時", "下午3点" … `NSTextCheckingResult` doesn't say whether a
    /// time was given, so look at the matched words.
    static func mentionsTimeOfDay(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil { return true }
        if lowered.range(of: #"\d\s*(am|pm|a\.m\.|p\.m\.|時|点|시)"#, options: .regularExpression) != nil { return true }
        return false
    }
}
