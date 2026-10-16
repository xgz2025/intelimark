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

/// A calendar file (`.ics`), as ticket sellers, airlines and rail apps attach to
/// their confirmations: the first event's name, start, end and place. A flight or
/// train in it (by its name) becomes a trip; anything else an event.
public enum CalendarFile {
    static let maxBytes = 1_000_000

    public static func read(from url: URL) -> StructuredData? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxBytes,
              let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8)
        else { return nil }
        return read(text)
    }

    public static func read(_ text: String) -> StructuredData? {
        guard let event = firstEvent(in: text), let start = event.start else { return nil }
        let summary = event.properties["SUMMARY"].map(unescape)
        let location = event.properties["LOCATION"].map(unescape)
        let description = event.properties["DESCRIPTION"].map(unescape)

        if let summary, var trip = TravelText.parse([summary, description].compactMap { $0 }.joined(separator: "\n"), needsDate: false) {
            if var leg = trip.legs.first {
                leg.departure = start.date
                leg.departureHasTime = start.hasTime
                leg.arrival = event.end?.date
                trip.legs[0] = leg
            }
            trip.origin = .calendarFile
            return StructuredData(kind: .travel, fields: TypedFields(trip: trip))
        }
        let ticket = TicketFields(
            name: summary, startDate: start.date, startHasTime: start.hasTime,
            endDate: event.end?.date, venue: location, origin: .calendarFile
        )
        return StructuredData(kind: .event, fields: TypedFields(ticket: ticket))
    }

    struct Event {
        var properties: [String: String] = [:]
        var start: (date: Date, hasTime: Bool)?
        var end: (date: Date, hasTime: Bool)?
    }

    /// The first VEVENT, with folded lines joined.
    static func firstEvent(in text: String) -> Event? {
        var lines: [String] = []
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in unified.components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(raw)
            }
        }
        var event: Event?
        for line in lines {
            if line == "BEGIN:VEVENT" { event = Event(); continue }
            if line == "END:VEVENT" { return event }
            guard event != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";").map(String.init)
            guard let name = parts.first?.uppercased() else { continue }
            let parameters = Dictionary(parts.dropFirst().compactMap { part -> (String, String)? in
                let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
                return pieces.count == 2 ? (pieces[0].uppercased(), pieces[1]) : nil
            }, uniquingKeysWith: { first, _ in first })
            switch name {
            case "DTSTART": event?.start = date(value, timeZone: parameters["TZID"])
            case "DTEND": event?.end = date(value, timeZone: parameters["TZID"])
            default: if event?.properties[name] == nil { event?.properties[name] = value }
            }
        }
        return nil
    }

    /// `20261024T193000Z`, `20261024T193000` (in `timeZone`, else local), `20261024`.
    static func date(_ value: String, timeZone identifier: String?) -> (date: Date, hasTime: Bool)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value.count == 8 {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            return formatter.date(from: value).map { ($0, false) }
        }
        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
        } else {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone = identifier.flatMap(TimeZone.init(identifier:)) ?? .current
        }
        return formatter.date(from: value).map { ($0, true) }
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
