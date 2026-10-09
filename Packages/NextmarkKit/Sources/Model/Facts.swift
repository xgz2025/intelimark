import Foundation

/// Where a fact about an item came from. Structured data beats the model;
/// model facts are only kept after grounding against the source text.
public enum FactSource: String, Codable, Sendable, Hashable {
    case structured, model, detector
}

/// A date that matters for an item — the input to time Moments (PRD M1).
public struct ItemDate: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable, Hashable, CaseIterable {
        case eventStart, eventEnd, deadline, expiry, reservation, mentioned
    }

    public var date: Date
    public var hasTime: Bool
    public var role: Role
    /// The words in the source that state the date, when known.
    public var evidence: String?
    public var source: FactSource

    public init(date: Date, hasTime: Bool, role: Role, evidence: String? = nil, source: FactSource) {
        self.date = date
        self.hasTime = hasTime
        self.role = role
        self.evidence = evidence
        self.source = source
    }
}

/// A specific place an item refers to — the input to place Moments (PRD M3).
public struct ItemPlace: Codable, Sendable, Hashable {
    public var name: String
    public var address: String?
    public var latitude: Double?
    public var longitude: Double?
    public var source: FactSource

    public init(name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil, source: FactSource) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
    }
}

extension TypedFields {
    /// Dates declared by the page's own schema.org data.
    public var structuredDates: [ItemDate] {
        guard let event else { return [] }
        var dates: [ItemDate] = []
        if let start = event.startDate {
            dates.append(ItemDate(date: start, hasTime: FactMerge.hasTimeOfDay(start), role: .eventStart, source: .structured))
        }
        if let end = event.endDate {
            dates.append(ItemDate(date: end, hasTime: FactMerge.hasTimeOfDay(end), role: .eventEnd, source: .structured))
        }
        return dates
    }

    /// Places declared by the page's own schema.org data.
    public var structuredPlaces: [ItemPlace] {
        if let place, let name = place.name ?? place.address {
            return [ItemPlace(name: name, address: place.address, latitude: place.latitude, longitude: place.longitude, source: .structured)]
        }
        if let event, let venue = event.venue {
            return [ItemPlace(name: venue, address: event.address, source: .structured)]
        }
        return []
    }
}

/// Combines structured and inferred facts: structured first, inferred facts that
/// repeat them are dropped.
public enum FactMerge {
    public static let maxDates = 8
    public static let maxPlaces = 5

    public static func dates(structured: [ItemDate], inferred: [ItemDate], calendar: Calendar = .current) -> [ItemDate] {
        var merged = structured
        for candidate in inferred {
            let duplicate = merged.contains { existing in
                calendar.isDate(existing.date, inSameDayAs: candidate.date)
                    && (existing.role == candidate.role || candidate.role == .mentioned)
            }
            if !duplicate { merged.append(candidate) }
        }
        return Array(merged.prefix(maxDates))
    }

    public static func places(structured: [ItemPlace], inferred: [ItemPlace]) -> [ItemPlace] {
        var merged = structured
        for candidate in inferred where !merged.contains(where: { $0.name.lowercased() == candidate.name.lowercased() }) {
            merged.append(candidate)
        }
        return Array(merged.prefix(maxPlaces))
    }

    /// schema.org dates without a time parse to midnight UTC.
    static func hasTimeOfDay(_ date: Date) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = utc.dateComponents([.hour, .minute, .second], from: date)
        return parts.hour != 0 || parts.minute != 0 || parts.second != 0
    }
}
