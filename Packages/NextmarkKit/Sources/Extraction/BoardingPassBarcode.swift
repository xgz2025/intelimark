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

/// The barcode on every airline boarding pass (IATA Bar Coded Boarding Pass,
/// format "M"): route, flight, day, seat and booking code at fixed positions. Read
/// from a photo or screenshot of the pass. It has the day, not the time.
public enum BoardingPassBarcode {
    public static func parse(_ message: String, near reference: Date = Date(), calendar: Calendar = .current) -> TripFields? {
        let characters = Array(message)
        guard characters.count >= 58, characters[0] == "M",
              let legCount = Int(String(characters[1])), (1...4).contains(legCount)
        else { return nil }

        func field(_ start: Int, _ length: Int) -> String? {
            guard start >= 0, start + length <= characters.count else { return nil }
            return String(characters[start..<(start + length)]).trimmingCharacters(in: .whitespaces)
        }

        var legs: [TripLeg] = []
        var bookingCode: String?
        // The first leg's mandatory items start at 23; each later leg's at the end of
        // the previous leg's conditional section.
        var position = 23
        for _ in 0..<legCount {
            guard let pnr = field(position, 7), let from = field(position + 7, 3), let to = field(position + 10, 3),
                  let carrier = field(position + 13, 3), let flight = field(position + 16, 5),
                  let julian = field(position + 21, 3), let seat = field(position + 25, 4),
                  isAirport(from), isAirport(to), !carrier.isEmpty, !flight.isEmpty
            else { break }
            bookingCode = bookingCode ?? (pnr.isEmpty ? nil : pnr)
            let number = String(flight.drop { $0 == "0" })
            legs.append(TripLeg(
                carrier: carrier,
                number: "\(carrier) \(number.isEmpty ? flight : number)",
                fromCode: from,
                toCode: to,
                departure: Int(julian).flatMap { day(ofYear: $0, near: reference, calendar: calendar) },
                departureHasTime: false,
                seat: normalizedSeat(seat)
            ))
            // Mandatory items end at position + 35, then a two-digit hex size of what follows.
            guard let size = field(position + 35, 2).flatMap({ Int($0, radix: 16) }) else { break }
            position += 37 + size
        }
        guard !legs.isEmpty else { return nil }
        return TripFields(mode: .flight, legs: legs, bookingCode: bookingCode, origin: .barcode)
    }

    static func isAirport(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase }
    }

    /// "032A" → "32A"; blank or "0000" → nil.
    static func normalizedSeat(_ seat: String) -> String? {
        let trimmed = String(seat.drop { $0 == "0" })
        return trimmed.isEmpty || !trimmed.contains(where: \.isNumber) ? nil : trimmed
    }

    /// The day `dayOfYear` in whichever year puts it closest to `reference`: the
    /// barcode has no year.
    static func day(ofYear dayOfYear: Int, near reference: Date, calendar: Calendar) -> Date? {
        guard (1...366).contains(dayOfYear) else { return nil }
        let year = calendar.component(.year, from: reference)
        let candidates = [year - 1, year, year + 1].compactMap { year -> Date? in
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return calendar.date(byAdding: .day, value: dayOfYear - 1, to: start)
        }
        return candidates.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
    }
}
