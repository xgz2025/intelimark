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

/// A date the model says it found, before grounding.
public struct DateCandidate: Sendable, Equatable {
    public var evidence: String
    public var isoDate: String
    public var role: ItemDate.Role

    public init(evidence: String, isoDate: String, role: ItemDate.Role) {
        self.evidence = evidence
        self.isoDate = isoDate
        self.role = role
    }
}

/// A place the model says it found, before grounding.
public struct PlaceCandidate: Sendable, Equatable {
    public var name: String
    public var address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

/// Keeps only model facts the source text supports (Docs/architecture.md §6.2):
/// a date's evidence must be quoted from the source and must state that day; a
/// place's name must appear in the source. Dates drive notifications, so a wrong
/// one is worse than a missing one.
public enum Grounding {
    public static func dates(from candidates: [DateCandidate], in source: String, calendar: Calendar = .current) -> [ItemDate] {
        let haystack = normalize(source)
        var grounded: [ItemDate] = []
        for candidate in candidates {
            let evidence = candidate.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !evidence.isEmpty, haystack.contains(normalize(evidence)),
                  let parsed = parseISODate(candidate.isoDate)
            else { continue }
            let (date, hasTime) = parsed

            // When the evidence holds a date the detector can read, it must be this one: "Oct 21"
            // never supports Nov 21. Only evidence the detector can't read ("the 21st") falls
            // back to stating the day number.
            let detected = DateFinder.matches(in: evidence)
            if detected.isEmpty {
                let day = calendar.component(.day, from: date)
                guard evidence.range(of: #"(?<!\d)0?\#(day)(?!\d)"#, options: .regularExpression) != nil else { continue }
            } else {
                guard detected.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { continue }
            }

            if !grounded.contains(where: { calendar.isDate($0.date, inSameDayAs: date) && $0.role == candidate.role }) {
                grounded.append(ItemDate(date: date, hasTime: hasTime, role: candidate.role, evidence: evidence, source: .model))
            }
        }
        return grounded
    }

    public static func places(from candidates: [PlaceCandidate], in source: String) -> [ItemPlace] {
        let haystack = normalize(source)
        var grounded: [ItemPlace] = []
        for candidate in candidates {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2, haystack.contains(normalize(name)),
                  !grounded.contains(where: { $0.name.lowercased() == name.lowercased() })
            else { continue }
            let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
            grounded.append(ItemPlace(
                name: name,
                address: !address.isEmpty && haystack.contains(normalize(address)) ? address : nil,
                source: .model
            ))
        }
        return grounded
    }

    /// `yyyy-MM-dd`, `yyyy-MM-ddTHH:mm[:ss]` (local time) or a full ISO 8601 timestamp.
    static func parseISODate(_ text: String) -> (Date, Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            iso.formatOptions = options
            if let date = iso.date(from: trimmed) { return (date, true) }
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for (format, hasTime) in [("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false)] {
            local.dateFormat = format
            if let date = local.date(from: trimmed) { return (date, hasTime) }
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension Grounding {
    /// A trip from the model's route and number, kept only when the content states them.
    public static func trip(from: String, to: String, number: String, departures dates: [ItemDate], in source: String) -> TripFields? {
        let lowered = source.lowercased()
        func grounded(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, lowered.contains(trimmed.lowercased()) else { return nil }
            return trimmed
        }
        let compactSource = lowered.replacingOccurrences(of: " ", with: "")
        let flightOrTrain = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let groundedNumber = flightOrTrain.count >= 3 && compactSource.contains(flightOrTrain.lowercased().replacingOccurrences(of: " ", with: ""))
            ? flightOrTrain : nil
        let origin = grounded(from)
        let destination = grounded(to)
        guard origin != nil || destination != nil else { return nil }
        let departure = dates.filter { $0.role == .departure || $0.role == .eventStart }.min { $0.date < $1.date }
        let mode: TripFields.Mode = {
            guard let groundedNumber, let first = groundedNumber.first else { return .other }
            let trainPrefixes: Set<Character> = ["G", "D", "C", "Z", "T", "K"]
            let digitsOnly = groundedNumber.dropFirst().allSatisfy(\.isNumber)
            return trainPrefixes.contains(first) && digitsOnly ? .train : .flight
        }()
        return TripFields(mode: mode, legs: [TripLeg(
            number: groundedNumber, from: origin, to: destination,
            departure: departure?.date, departureHasTime: departure?.hasTime ?? true
        )], origin: .model)
    }
}
