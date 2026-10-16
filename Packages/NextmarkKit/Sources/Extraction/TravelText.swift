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

/// Flights and trains read from text: a ticket's or itinerary's PDF, the text in a
/// screenshot of one, a calendar event's name. Says nothing unless the text clearly
/// is one: a flight number with a route or the word "flight", or a train number
/// between two stations.
public enum TravelText {
    /// - Parameter needsDate: False when the date comes from elsewhere (a calendar
    ///   event's start): the route and number are enough.
    public static func parse(
        _ text: String, reference: Date = Date(), calendar: Calendar = .current, needsDate: Bool = true
    ) -> TripFields? {
        chineseTrain(text, reference: reference, calendar: calendar, needsDate: needsDate)
            ?? flight(text, reference: reference, calendar: calendar, needsDate: needsDate)
    }

    // MARK: Flights

    static let flightWords = ["flight", "boarding pass", "boarding", "itinerary", "e-ticket", "航班", "登机", "机票", "行程单"]
    static let departureWords = ["departure", "departs", "depart", "dep", "起飞", "出发", "计划起飞"]

    static func flight(_ text: String, reference: Date, calendar: Calendar, needsDate: Bool) -> TripFields? {
        let lowered = text.lowercased()
        let pair = text.firstMatch(of: #/\b([A-Z]{3})\s*(?:→|->|–|—|-|>|to|至|飞往)\s*([A-Z]{3})\b/#)
        let numbers = text.matches(of: #/\b([A-Z][A-Z0-9]|[0-9][A-Z])\s?(\d{2,4})(?![\d:：])/#)
        guard pair != nil || flightWords.contains(where: lowered.contains),
              let number = numbers.first(where: { isFlightNumber(String($0.output.1)) })
        else { return nil }
        let carrier = String(number.output.1)
        var leg = TripLeg(
            carrier: carrier,
            number: "\(carrier) \(String(number.output.2).drop { $0 == "0" })",
            fromCode: pair.map { String($0.output.1) },
            toCode: pair.map { String($0.output.2) }
        )
        let when = departure(in: text, keywords: departureWords, reference: reference, calendar: calendar)
        guard when != nil || !needsDate else { return nil }
        leg.departure = when?.date
        leg.departureHasTime = when?.hasTime ?? true
        leg.seat = text.firstMatch(of: #/(?:seat|座位)[:：\s]*(\d{1,2}[A-K])\b/#.ignoresCase()).map { String($0.output.1) }
        leg.gate = text.firstMatch(of: #/(?:gate|登机口)[:：\s]*([A-Z]?\d{1,3}[A-Z]?)\b/#.ignoresCase()).map { String($0.output.1) }
        leg.terminal = text.firstMatch(of: #/(?:terminal|航站楼)[:：\s]*(T?\d|[A-Z])\b/#.ignoresCase()).map { String($0.output.1) }
        return TripFields(mode: .flight, legs: [leg], bookingCode: booking(in: text), origin: .text)
    }

    /// A carrier code, and not a common look-alike: a time of day, a size, a unit.
    static func isFlightNumber(_ carrier: String) -> Bool {
        let notCarriers: Set<String> = ["AM", "PM", "UK", "US", "EU", "NO", "ID", "PO", "TV", "MB", "GB", "KG", "CM", "MM", "T1", "T2", "T3"]
        return !notCarriers.contains(carrier)
    }

    // MARK: Chinese railway tickets (12306)


    static func chineseTrain(_ text: String, reference: Date, calendar: Calendar, needsDate: Bool) -> TripFields? {
        let stations = text.matches(of: #/(\p{Han}{2,8})\s?站/#).map { String($0.output.1) + "站" }
        guard stations.count >= 2, stations[0] != stations[1],
              let number = text.firstMatch(of: #/(?:^|[^A-Za-z0-9])([GDCZTKYLS]\d{1,4})(?!\d)/#)
        else { return nil }
        var leg = TripLeg(carrier: nil, number: String(number.output.1), from: stations[0], to: stations[1])
        let when = departure(in: text, keywords: ["开", "发车", "出发"], reference: reference, calendar: calendar, keywordsFollowTime: true)
        guard when != nil || !needsDate else { return nil }
        leg.departure = when?.date
        leg.departureHasTime = when?.hasTime ?? true
        if let seat = text.firstMatch(of: #/(\d{1,2})车(\d{1,3}[A-F]?)号/#) {
            leg.seat = "\(seat.output.1)车\(seat.output.2)号"
        }
        return TripFields(mode: .train, legs: [leg], bookingCode: booking(in: text), origin: .text)
    }

    // MARK: Dates


    /// The departure: a full date in the text, at the time next to a departure word
    /// (or the first time after the date that isn't a boarding time).
    static func departure(
        in text: String, keywords: [String], reference: Date, calendar: Calendar, keywordsFollowTime: Bool = false
    ) -> (date: Date, hasTime: Bool)? {
        guard let day = firstDay(in: text, reference: reference, calendar: calendar) else { return nil }
        let times = text.matches(of: #/(?:^|\D)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)/#)
        var chosen: (Int, Int)?
        for match in times {
            let around = keywordsFollowTime
                ? String(text[match.range.upperBound...].prefix(3))
                : String(text[..<match.range.lowerBound].suffix(24)).lowercased()
            if keywords.contains(where: around.contains) {
                chosen = (Int(match.output.1) ?? 0, Int(match.output.2) ?? 0)
                break
            }
        }
        if chosen == nil, !keywordsFollowTime {
            let before = times.first { match in
                let preceding = String(text[..<match.range.lowerBound].suffix(16)).lowercased()
                return !preceding.contains("board") && !preceding.contains("登机") && !preceding.contains("check")
            }
            chosen = before.map { (Int($0.output.1) ?? 0, Int($0.output.2) ?? 0) }
        }
        guard let chosen else { return (day, false) }
        let (hour, minute) = chosen
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day).map { ($0, true) } ?? (day, false)
    }

    /// The first full date: "2026-10-20", "2026年10月20日", or one the system reads
    /// ("20 Oct 2026", "Oct 20, 2026").
    static func firstDay(in text: String, reference: Date, calendar: Calendar) -> Date? {
        if let match = text.firstMatch(of: #/(20\d{2})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})日?/#),
           let year = Int(match.output.1), let month = Int(match.output.2), let day = Int(match.output.3),
           let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
            return date
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let date = match.date, let range = Range(match.range, in: text),
                  text[range].contains(where: \.isNumber), text[range].contains(where: \.isLetter)
                    || text[range].firstMatch(of: #/\b20\d{2}\b/#) != nil,
                  abs(date.timeIntervalSince(reference)) < 2 * 365 * 86_400
            else { continue }
            return calendar.startOfDay(for: date)
        }
        return nil
    }

    static func booking(in text: String) -> String? {
        let pattern = #/(?:PNR|booking (?:ref(?:erence)?|code)|confirmation(?: (?:code|number))?|record locator|订座记录|确认号|订单号)[:：#\s]*([A-Z0-9]{5,8})\b/#
        return text.firstMatch(of: pattern.ignoresCase()).map { String($0.output.1) }
    }
}
