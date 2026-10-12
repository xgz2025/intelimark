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

/// Deterministic date detection with `NSDataDetector`: the fallback understander's
/// date source, and the check model-proposed dates must pass (Docs/architecture.md §6.2).
public enum DateFinder {
    public struct Match: Sendable, Equatable {
        /// The date the words name. For "ends Oct 31" / "until Nov 1" this is the end.
        public var date: Date
        /// True for open-ended ranges ("sale ends …", "refunds until …"): a deadline.
        public var isUntil: Bool
        public var hasTime: Bool
        /// False when the words only state a time ("11:59 PM"): the detector then
        /// assumes today, which is not a fact from the source.
        public var mentionsDay: Bool
        public var text: String
    }

    static let maxScannedCharacters = 20_000
    /// How close to "now" a range start must be to count as open-ended.
    static let openEndedTolerance: TimeInterval = 120

    public static func matches(in text: String) -> [Match] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return [] }
        let scanned = String(text.prefix(maxScannedCharacters))
        let now = Date()
        return detector.matches(in: scanned, range: NSRange(scanned.startIndex..., in: scanned)).compactMap { result in
            guard let start = result.date, let range = Range(result.range, in: scanned) else { return nil }
            let matched = String(scanned[range])
            // "ends October 31" / "until Nov 1" come back as a range from today with a
            // duration; the date the words name is the end of that range.
            let isUntil = result.duration > 0 && isOpenEndedStart(start, now: now)
            let date = isUntil ? start.addingTimeInterval(result.duration) : start
            return Match(
                date: date, isUntil: isUntil, hasTime: mentionsTimeOfDay(matched),
                mentionsDay: mentionsDay(matched), text: matched
            )
        }
    }

    /// The start NSDataDetector gives an open-ended range: the current time when the
    /// end has a time ("ends Oct 31 at 11:59 PM"), noon today when it doesn't
    /// ("until November 1"). A stated range that starts today at noon reads the same;
    /// it then resolves to its end, which is still a date from the source.
    static func isOpenEndedStart(_ start: Date, now: Date, calendar: Calendar = .current) -> Bool {
        if abs(start.timeIntervalSince(now)) < openEndedTolerance { return true }
        guard calendar.isDate(start, inSameDayAs: now) else { return false }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: start)
        return parts.hour == 12 && parts.minute == 0 && parts.second == 0
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
