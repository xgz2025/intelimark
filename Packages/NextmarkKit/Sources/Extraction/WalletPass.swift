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

/// A Wallet pass (`.pkpass`): boarding passes and event tickets say exactly what,
/// where and when, in `pass.json`. Its semantic tags are read first, then its
/// fields, then the boarding pass barcode.
public enum WalletPass {
    public static func read(from url: URL) -> StructuredData? {
        guard let archive = ZipArchive(url: url), let json = archive.contents(of: "pass.json") else { return nil }
        return read(passJSON: json)
    }

    public static func read(passJSON data: Data) -> StructuredData? {
        guard let pass = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let semantics = pass["semantics"] as? [String: Any] ?? [:]
        let organization = text(pass["organizationName"])
        let relevant = date(pass["relevantDate"])
            ?? ((pass["relevantDates"] as? [[String: Any]])?.first).flatMap { date($0["startDate"] ?? $0["date"]) }
        let barcode = ((pass["barcodes"] as? [[String: Any]])?.first ?? pass["barcode"] as? [String: Any])
            .flatMap { text($0["message"]) }

        if let boarding = pass["boardingPass"] as? [String: Any] {
            let fields = allFields(boarding)
            let mode: TripFields.Mode = switch text(boarding["transitType"]) {
            case "PKTransitTypeAir": .flight
            case "PKTransitTypeTrain": .train
            case "PKTransitTypeBus": .bus
            case "PKTransitTypeBoat": .boat
            default: .other
            }
            let fromBarcode = barcode.flatMap { BoardingPassBarcode.parse($0) }
            var leg = fromBarcode?.legs.first ?? TripLeg()
            let origin = field(fields, keys: ["origin", "from", "depart"])
            let destination = field(fields, keys: ["destination", "dest", "arriv"])
            leg.fromCode = text(semantics["departureAirportCode"]) ?? (mode == .flight ? origin?.value.uppercased() : nil) ?? leg.fromCode
            leg.from = text(semantics["departureAirportName"]) ?? text(semantics["departureStationName"])
                ?? text(semantics["departureLocationDescription"]) ?? origin?.label ?? (mode == .flight ? nil : origin?.value) ?? leg.from
            leg.toCode = text(semantics["destinationAirportCode"]) ?? (mode == .flight ? destination?.value.uppercased() : nil) ?? leg.toCode
            leg.to = text(semantics["destinationAirportName"]) ?? text(semantics["destinationStationName"])
                ?? text(semantics["destinationLocationDescription"]) ?? destination?.label ?? (mode == .flight ? nil : destination?.value) ?? leg.to
            let airline = text(semantics["airlineCode"])
            let number = text(semantics["flightNumber"]).map { [airline, $0].compactMap { $0 }.joined(separator: " ") }
                ?? text(semantics["flightCode"]) ?? text(semantics["vehicleNumber"])
                ?? field(fields, keys: ["flight", "train", "trip", "vehicle"])?.value
            leg.number = number ?? leg.number
            leg.carrier = organization ?? text(semantics["transitProvider"]) ?? leg.carrier
            if let departure = date(semantics["currentDepartureDate"]) ?? date(semantics["originalDepartureDate"]) ?? relevant {
                leg.departure = departure
                leg.departureHasTime = true
            }
            leg.arrival = date(semantics["currentArrivalDate"]) ?? date(semantics["originalArrivalDate"])
            leg.gate = text(semantics["departureGate"]) ?? field(fields, keys: ["gate"])?.value ?? leg.gate
            leg.terminal = text(semantics["departureTerminal"]) ?? field(fields, keys: ["terminal"])?.value
            leg.platform = text(semantics["departurePlatform"]) ?? field(fields, keys: ["platform"])?.value
            leg.seat = ((semantics["seats"] as? [[String: Any]])?.first).flatMap { text($0["seatNumber"]) }
                ?? field(fields, keys: ["seat"])?.value ?? leg.seat
            guard leg.from != nil || leg.fromCode != nil || leg.to != nil || leg.toCode != nil || leg.departure != nil else { return nil }
            let booking = text(semantics["confirmationNumber"]) ?? field(fields, keys: ["confirmation", "booking", "pnr", "record"])?.value
                ?? fromBarcode?.bookingCode
            return StructuredData(kind: .travel, fields: TypedFields(trip: TripFields(
                mode: mode, legs: [leg], bookingCode: booking, origin: .walletPass
            )))
        }

        if let event = pass["eventTicket"] as? [String: Any] {
            let fields = allFields(event)
            let ticket = TicketFields(
                name: text(semantics["eventName"]) ?? field(fields, keys: ["event", "show", "title", "name"])?.value
                    ?? text(pass["description"]),
                startDate: date(semantics["eventStartDate"]) ?? relevant,
                doorsAt: date(semantics["eventDoorsOpenDate"]),
                endDate: date(semantics["eventEndDate"]),
                venue: text(semantics["venueName"]) ?? field(fields, keys: ["venue", "location"])?.value,
                address: text((semantics["venueLocation"] as? [String: Any])?["address"]),
                seat: seat(semantics) ?? field(fields, keys: ["seat"])?.value,
                bookingCode: text(semantics["confirmationNumber"]) ?? field(fields, keys: ["order", "confirmation", "booking"])?.value,
                origin: .walletPass
            )
            guard ticket.name != nil || ticket.startDate != nil else { return nil }
            return StructuredData(kind: .ticket, fields: TypedFields(ticket: ticket))
        }
        return nil
    }

    struct Field {
        let key: String
        let label: String?
        let value: String
    }

    static func allFields(_ style: [String: Any]) -> [Field] {
        ["headerFields", "primaryFields", "secondaryFields", "auxiliaryFields", "backFields"]
            .flatMap { (style[$0] as? [[String: Any]]) ?? [] }
            .compactMap { field in
                guard let key = text(field["key"]), let value = text(field["value"]) else { return nil }
                return Field(key: key.lowercased(), label: text(field["label"]), value: value)
            }
    }

    /// The first field whose key (or label) mentions one of `keys`.
    static func field(_ fields: [Field], keys: [String]) -> Field? {
        for key in keys {
            if let match = fields.first(where: { $0.key.contains(key) || ($0.label?.lowercased().contains(key) ?? false) }) {
                return match
            }
        }
        return nil
    }

    static func seat(_ semantics: [String: Any]) -> String? {
        guard let seat = (semantics["seats"] as? [[String: Any]])?.first else { return nil }
        let parts = [text(seat["seatSection"]), text(seat["seatRow"]), text(seat["seatNumber"])].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func text(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        SchemaDate.parse(text(value))
    }
}
