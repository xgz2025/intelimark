import Foundation

/// Deterministic date detection with `NSDataDetector`: the fallback understander's
/// date source, and the check model-proposed dates must pass (Docs/architecture.md §6.2).
public enum DateFinder {
    public struct Match: Sendable, Equatable {
        public var date: Date
        public var hasTime: Bool
        /// False when the words only state a time ("11:59 PM"): the detector then
        /// assumes today, which is not a fact from the source.
        public var mentionsDay: Bool
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
            return Match(date: date, hasTime: mentionsTimeOfDay(matched), mentionsDay: mentionsDay(matched), text: matched)
        }
    }

    static let timeOfDayPattern = #"\d{1,2}[:.]\d{2}(\s*(am|pm|a\.m\.|p\.m\.))?|\d{1,2}\s*(am|pm|a\.m\.|p\.m\.|時|点|시)"#

    /// "7:30", "7pm", "19時", "下午3点" … `NSTextCheckingResult` doesn't say whether a
    /// time was given, so look at the matched words.
    static func mentionsTimeOfDay(_ text: String) -> Bool {
        text.lowercased().range(of: timeOfDayPattern, options: .regularExpression) != nil
    }

    /// Whether anything besides a time of day is stated: a number ("Oct 31") or a
    /// word ("tomorrow", "Friday", "明天").
    static func mentionsDay(_ text: String) -> Bool {
        let withoutTimes = text.lowercased().replacingOccurrences(of: timeOfDayPattern, with: " ", options: .regularExpression)
        let ignored: Set<String> = ["at", "on", "by", "@", "-", "–", "from", "to", "until"]
        let remaining = withoutTimes
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignored.contains($0) }
        return !remaining.isEmpty
    }
}
