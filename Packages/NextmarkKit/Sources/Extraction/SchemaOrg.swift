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

/// Maps schema.org JSON-LD to a `StructuredData` (Docs/architecture.md §6.2:
/// "facts from structure first"). Picks the most specific entity on the page:
/// product > recipe > event > place > video > article.
public enum SchemaOrg {
    public static func structuredData(fromJSONLD blocks: [String]) -> StructuredData? {
        let nodes = blocks.flatMap { block -> [[String: Any]] in
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { return [] }
            return collectNodes(json)
        }
        // Bookings say exactly what was bought: they win over anything else on the page.
        if let trip = trip(from: nodes) {
            return StructuredData(kind: .travel, fields: TypedFields(trip: trip))
        }
        if let ticket = ticket(from: nodes) {
            return StructuredData(kind: .ticket, fields: TypedFields(ticket: ticket))
        }
        let ranked = nodes.compactMap { node -> (rank: Int, kind: SemanticKind, node: [String: Any])? in
            guard let match = classify(types(of: node)) else { return nil }
            return (match.0, match.1, node)
        }
        guard let best = ranked.min(by: { $0.rank < $1.rank }) else { return nil }
        return StructuredData(kind: best.kind, fields: fields(for: best.kind, from: best.node))
    }

    // MARK: Node discovery

    static func collectNodes(_ json: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 4 else { return [] }
        if let array = json as? [Any] {
            return array.flatMap { collectNodes($0, depth: depth + 1) }
        }
        guard let object = json as? [String: Any] else { return [] }
        var nodes: [[String: Any]] = []
        if object["@type"] != nil { nodes.append(object) }
        if let graph = object["@graph"] { nodes += collectNodes(graph, depth: depth + 1) }
        if let main = object["mainEntity"] { nodes += collectNodes(main, depth: depth + 1) }
        return nodes
    }

    // MARK: Bookings

    static let tripTypes: [String: TripFields.Mode] = [
        "FlightReservation": .flight, "Flight": .flight,
        "TrainReservation": .train, "TrainTrip": .train,
        "BusReservation": .bus, "BusTrip": .bus,
        "BoatReservation": .boat, "BoatTrip": .boat,
    ]

    /// Every flight, train, bus or boat booked on the page (an itinerary lists several).
    static func trip(from nodes: [[String: Any]]) -> TripFields? {
        var mode: TripFields.Mode?
        var legs: [TripLeg] = []
        var bookingCode: String?
        var seen = Set<String>()
        for node in nodes {
            guard let nodeMode = types(of: node).compactMap({ tripTypes[$0] }).first else { continue }
            let isReservation = types(of: node).contains { $0.hasSuffix("Reservation") }
            let journey = isReservation ? first(node["reservationFor"]) ?? [:] : node
            var leg = tripLeg(journey, mode: nodeMode)
            if isReservation {
                bookingCode = bookingCode ?? string(node["reservationNumber"])
                leg.seat = leg.seat ?? string(first(node["airplaneSeat"])?["seatNumber"]) ?? string(node["airplaneSeat"])
                    ?? first(node["reservedTicket"]).flatMap { string(first($0["ticketedSeat"])?["seatNumber"]) }
            }
            // A page can list the same leg twice (a reservation and its flight).
            let key = [leg.number, leg.fromCode ?? leg.from, leg.departure.map { "\($0.timeIntervalSince1970)" }]
                .compactMap { $0 }.joined(separator: "|")
            guard leg.from != nil || leg.fromCode != nil || leg.departure != nil, seen.insert(key).inserted else { continue }
            mode = mode ?? nodeMode
            legs.append(leg)
        }
        guard let mode, !legs.isEmpty else { return nil }
        legs.sort { ($0.departure ?? .distantFuture) < ($1.departure ?? .distantFuture) }
        return TripFields(mode: mode, legs: legs, bookingCode: bookingCode, origin: .page)
    }

    static func tripLeg(_ journey: [String: Any], mode: TripFields.Mode) -> TripLeg {
        func stop(_ keys: [String]) -> [String: Any]? {
            keys.lazy.compactMap { first(journey[$0]) }.first
        }
        let from = stop(["departureAirport", "departureStation", "departureBusStop", "departureBoatTerminal"])
        let to = stop(["arrivalAirport", "arrivalStation", "arrivalBusStop", "arrivalBoatTerminal"])
        let carrier = name(of: journey["airline"]) ?? name(of: journey["provider"]) ?? string(first(journey["airline"])?["iataCode"])
        let airlineCode = string(first(journey["airline"])?["iataCode"])
        let number = string(journey["flightNumber"]).map { number in
            guard let airlineCode, !number.hasPrefix(airlineCode) else { return number }
            return "\(airlineCode) \(number)"
        } ?? string(journey["trainNumber"]) ?? string(journey["busNumber"]) ?? string(journey["trainName"])
        let departureText = string(journey["departureTime"])
        return TripLeg(
            carrier: carrier,
            number: number,
            from: from.flatMap { string($0["name"]) } ?? string(journey["departureAirport"]),
            fromCode: from.flatMap { string($0["iataCode"]) },
            to: to.flatMap { string($0["name"]) } ?? string(journey["arrivalAirport"]),
            toCode: to.flatMap { string($0["iataCode"]) },
            departure: SchemaDate.parse(departureText),
            departureHasTime: departureText.map { $0.contains("T") } ?? true,
            arrival: SchemaDate.parse(string(journey["arrivalTime"])),
            terminal: string(journey["departureTerminal"]),
            gate: string(journey["departureGate"]),
            platform: string(journey["departurePlatform"])
        )
    }

    /// A ticket bought for a show, concert, game or film.
    static func ticket(from nodes: [[String: Any]]) -> TicketFields? {
        guard let reservation = nodes.first(where: { types(of: $0).contains("EventReservation") }),
              let event = first(reservation["reservationFor"])
        else { return nil }
        let location = first(event["location"])
        let startText = string(event["startDate"])
        let seat = first(reservation["reservedTicket"]).flatMap { first($0["ticketedSeat"]) }.map { seat in
            [string(seat["seatSection"]), string(seat["seatRow"]), string(seat["seatNumber"])].compactMap { $0 }.joined(separator: " · ")
        }
        return TicketFields(
            name: string(event["name"]),
            startDate: SchemaDate.parse(startText),
            startHasTime: startText.map { $0.contains("T") } ?? true,
            doorsAt: SchemaDate.parse(string(event["doorTime"])),
            endDate: SchemaDate.parse(string(event["endDate"])),
            venue: location.flatMap { string($0["name"]) } ?? string(event["location"]),
            address: location.flatMap { address($0["address"]) },
            seat: seat.flatMap { $0.isEmpty ? nil : $0 },
            bookingCode: string(reservation["reservationNumber"]),
            origin: .page
        )
    }

    static func types(of node: [String: Any]) -> [String] {
        let raw: [String]
        if let single = node["@type"] as? String {
            raw = [single]
        } else {
            raw = node["@type"] as? [String] ?? []
        }
        return raw.map { $0.components(separatedBy: "/").last ?? $0 }
    }

    static let placeTypes: Set<String> = [
        "Place", "LocalBusiness", "Restaurant", "Hotel", "LodgingBusiness", "FoodEstablishment",
        "TouristAttraction", "Store", "CafeOrCoffeeShop", "BarOrPub", "Bakery", "Museum", "Park",
        "Landmark", "Resort", "BedAndBreakfast", "Hostel", "Motel",
    ]
    static let articleTypes: Set<String> = [
        "Article", "NewsArticle", "BlogPosting", "TechArticle", "ScholarlyArticle", "Report", "AnalysisNewsArticle",
    ]

    static func classify(_ types: [String]) -> (Int, SemanticKind)? {
        var best: (Int, SemanticKind)?
        func consider(_ rank: Int, _ kind: SemanticKind) {
            if best == nil || rank < best!.0 { best = (rank, kind) }
        }
        for type in types {
            switch type {
            case "Product", "ProductGroup", "IndividualProduct", "ProductModel": consider(0, .product)
            case "Recipe": consider(1, .recipe)
            case _ where type.hasSuffix("Event"): consider(2, .event)
            case _ where placeTypes.contains(type) || type.hasSuffix("Business"): consider(3, .place)
            case "VideoObject": consider(4, .video)
            case _ where articleTypes.contains(type): consider(5, .article)
            default: break
            }
        }
        return best
    }

    // MARK: Fields

    static func fields(for kind: SemanticKind, from node: [String: Any]) -> TypedFields {
        switch kind {
        case .product: TypedFields(product: product(node))
        case .recipe: TypedFields(recipe: recipe(node))
        case .event: TypedFields(event: event(node))
        case .place: TypedFields(place: place(node))
        case .article: TypedFields(article: article(node))
        default: TypedFields()
        }
    }

    static func product(_ node: [String: Any]) -> ProductFields {
        let offer = first(node["offers"]).flatMap { offers -> [String: Any]? in
            // AggregateOffer nests the real offers one level down.
            if let nested = first(offers["offers"]) { return nested }
            return offers
        }
        let price = number(offer?["price"]) ?? number(offer?["lowPrice"])
            ?? number(first(offer?["priceSpecification"])?["price"])
        return ProductFields(
            name: string(node["name"]),
            brand: name(of: node["brand"]),
            price: price,
            currency: string(offer?["priceCurrency"]) ?? string(first(offer?["priceSpecification"])?["priceCurrency"]),
            availability: string(offer?["availability"]).map { $0.components(separatedBy: "/").last ?? $0 },
            description: string(node["description"]).map { String($0.prefix(500)) },
            imageURL: imageURL(node["image"]),
            store: name(of: offer?["seller"]),
            origin: .page
        )
    }

    static func place(_ node: [String: Any]) -> PlaceFields {
        let geo = first(node["geo"])
        return PlaceFields(
            name: string(node["name"]),
            address: address(node["address"]),
            latitude: number(geo?["latitude"]),
            longitude: number(geo?["longitude"]),
            telephone: string(node["telephone"])
        )
    }

    static func event(_ node: [String: Any]) -> EventFields {
        let location = first(node["location"])
        return EventFields(
            name: string(node["name"]),
            startDate: SchemaDate.parse(string(node["startDate"])),
            endDate: SchemaDate.parse(string(node["endDate"])),
            venue: location.flatMap { string($0["name"]) } ?? string(node["location"]),
            address: location.flatMap { address($0["address"]) }
        )
    }

    static func recipe(_ node: [String: Any]) -> RecipeFields {
        let ingredients = (node["recipeIngredient"] ?? node["ingredients"]) as? [Any] ?? []
        let total = SchemaDuration.minutes(string(node["totalTime"]))
            ?? zip2(SchemaDuration.minutes(string(node["prepTime"])), SchemaDuration.minutes(string(node["cookTime"])))
        let servings: String? = {
            if let array = node["recipeYield"] as? [Any] { return array.first.flatMap { scalarString($0) } }
            return scalarString(node["recipeYield"])
        }()
        return RecipeFields(
            name: string(node["name"]),
            ingredients: ingredients.compactMap { scalarString($0) }.map(HTMLText.collapseWhitespace).filter { !$0.isEmpty },
            totalMinutes: total,
            servings: servings
        )
    }

    static func article(_ node: [String: Any]) -> ArticleFields {
        ArticleFields(
            headline: string(node["headline"]) ?? string(node["name"]),
            author: name(of: node["author"]),
            publisher: name(of: node["publisher"]),
            publishedAt: SchemaDate.parse(string(node["datePublished"]))
        )
    }

    // MARK: Value helpers

    /// `"https://…"`, `["https://…"]` or `{"url": "https://…"}`.
    static func imageURL(_ value: Any?) -> String? {
        if let text = string(value), text.hasPrefix("http") { return text }
        if let array = value as? [Any] { return array.lazy.compactMap { imageURL($0) }.first }
        if let object = value as? [String: Any] { return imageURL(object["url"] ?? object["contentUrl"]) }
        return nil
    }

    /// The first object of a value that may be an object or an array of objects.
    static func first(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        return (value as? [Any])?.lazy.compactMap { $0 as? [String: Any] }.first
    }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let cleaned = HTMLText.collapseWhitespace(HTMLText.decodeEntities(text))
        return cleaned.isEmpty ? nil : cleaned
    }

    static func scalarString(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
        }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    /// `"Ann"`, `{"name": "Ann"}` or `[{"name": "Ann"}, …]` → `"Ann"`.
    static func name(of value: Any?) -> String? {
        if let text = string(value) { return text }
        if let object = first(value) { return string(object["name"]) }
        return nil
    }

    static func address(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        guard let object = first(value) else { return nil }
        let country = string(object["addressCountry"]) ?? name(of: object["addressCountry"])
        let parts = [
            string(object["streetAddress"]), string(object["addressLocality"]),
            string(object["addressRegion"]), string(object["postalCode"]), country,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func zip2(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case let (a?, b?): a.addingReportingOverflow(b).overflow ? nil : a + b
        case let (a?, nil): a
        case let (nil, b?): b
        default: nil
        }
    }
}

enum SchemaDate {
    static func parse(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
        ] {
            iso.formatOptions = options
            if let date = iso.date(from: text) { return date }
        }
        // With an offset but no seconds ("2026-10-20T14:05+08:00"), as Wallet passes write it.
        let offset = DateFormatter()
        offset.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"] {
            offset.dateFormat = format
            if let date = offset.date(from: text) { return date }
        }
        // Local date-times without an offset are common for events. A date alone
        // ("2026-11-21") is that day where the user is: local midnight, which
        // `FactMerge.hasTimeOfDay` reads as "no time". Parsed as UTC it would land on
        // the previous evening west of Greenwich.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }
}

enum SchemaDuration {
    static let pattern = HTMLText.regex(#"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#)

    static let maxMinutes: Double = 366 * 24 * 60

    /// ISO 8601 durations such as `PT1H15M` → minutes.
    static func minutes(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).uppercased(), text.hasPrefix("P"),
              let groups = HTMLText.matches(pattern, in: text).first
        else { return nil }
        // A page can claim any number of digits: parse as Double so nothing overflows,
        // and ignore anything longer than a year.
        let days = groups[1].flatMap { Double($0) } ?? 0
        let hours = groups[2].flatMap { Double($0) } ?? 0
        let minutes = groups[3].flatMap { Double($0) } ?? 0
        let total = days * 24 * 60 + hours * 60 + minutes
        guard total > 0, total <= maxMinutes else { return nil }
        return Int(total)
    }
}
