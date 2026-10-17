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
import Testing
import Model
@testable import Extraction

struct WalletPassTests {
    @Test func aBoardingPassIsAFlight() throws {
        let json = """
            {"formatVersion":1,"organizationName":"China Eastern","description":"Boarding pass",
             "relevantDate":"2026-10-20T14:05+08:00",
             "semantics":{"airlineCode":"MU","flightNumber":523,"departureAirportCode":"PVG","departureAirportName":"Shanghai Pudong",
                          "destinationAirportCode":"NRT","destinationAirportName":"Tokyo Narita","departureGate":"D12",
                          "seats":[{"seatNumber":"32A"}],"confirmationNumber":"ABC123"},
             "boardingPass":{"transitType":"PKTransitTypeAir","primaryFields":[{"key":"origin","label":"Shanghai","value":"PVG"},
                             {"key":"destination","label":"Tokyo","value":"NRT"}]}}
            """
        let structured = try #require(WalletPass.read(passJSON: Data(json.utf8)))
        #expect(structured.kind == .travel)
        let trip = try #require(structured.fields.trip)
        #expect(trip.mode == .flight)
        #expect(trip.bookingCode == "ABC123")
        #expect(trip.origin == .walletPass)
        let leg = try #require(trip.legs.first)
        #expect(leg.number == "MU 523")
        #expect(leg.fromCode == "PVG")
        #expect(leg.to == "Tokyo Narita")
        #expect(leg.seat == "32A")
        #expect(leg.gate == "D12")
        #expect(leg.departure == Date(timeIntervalSince1970: 1_792_476_300))
    }

    @Test func anEventTicketIsAShow() throws {
        let json = """
            {"formatVersion":1,"organizationName":"Ticketmaster","description":"Ticket","relevantDate":"2026-11-21T19:30:00Z",
             "eventTicket":{"primaryFields":[{"key":"event","label":"EVENT","value":"Swan Lake"}],
                            "secondaryFields":[{"key":"venue","label":"VENUE","value":"Royal Opera House"},
                                               {"key":"seat","label":"SEAT","value":"Row F 12"}]}}
            """
        let structured = try #require(WalletPass.read(passJSON: Data(json.utf8)))
        #expect(structured.kind == .ticket)
        let ticket = try #require(structured.fields.ticket)
        #expect(ticket.name == "Swan Lake")
        #expect(ticket.venue == "Royal Opera House")
        #expect(ticket.seat == "Row F 12")
        #expect(ticket.startDate == Date(timeIntervalSince1970: 1_795_289_400))
    }
}

struct BoardingPassBarcodeTests {
    @Test func readsTheRouteFlightDaySeatAndBooking() throws {
        let message = "M1DESMARAIS/LUC       EABC123 YULFRAAC 0834 326J001A0025 100"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let reference = Date(timeIntervalSince1970: 1_792_000_000)   // Oct 2026
        let trip = try #require(BoardingPassBarcode.parse(message, near: reference, calendar: calendar))
        let leg = try #require(trip.legs.first)
        #expect(leg.fromCode == "YUL")
        #expect(leg.toCode == "FRA")
        #expect(leg.number == "AC 834")
        #expect(leg.seat == "1A")
        #expect(trip.bookingCode == "ABC123")
        #expect(!leg.departureHasTime)
        // Day 326 of 2026 is November 22.
        #expect(leg.departure == calendar.date(from: DateComponents(year: 2026, month: 11, day: 22)))
    }

    @Test func otherBarcodesAreNotBoardingPasses() {
        #expect(BoardingPassBarcode.parse("https://example.com/ticket/123") == nil)
        #expect(BoardingPassBarcode.parse("4006381333931") == nil)
    }
}

struct CalendarFileTests {
    @Test func anEventIsAShowAtItsVenue() throws {
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Swan Lake\r\nDTSTART:20261121T193000Z\r\nDTEND:20261121T220000Z\r\nLOCATION:Royal Opera House\\, London\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let structured = try #require(CalendarFile.read(ics))
        #expect(structured.kind == .event)
        let ticket = try #require(structured.fields.ticket)
        #expect(ticket.name == "Swan Lake")
        #expect(ticket.venue == "Royal Opera House, London")
        #expect(ticket.startDate == Date(timeIntervalSince1970: 1_795_289_400))
        #expect(ticket.origin == .calendarFile)
    }

    @Test func aFlightInACalendarIsATrip() throws {
        let ics = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Flight MU523 PVG → NRT\nDTSTART:20261020T060500Z\nEND:VEVENT\nEND:VCALENDAR\n"
        let structured = try #require(CalendarFile.read(ics))
        #expect(structured.kind == .travel)
        let leg = try #require(structured.fields.trip?.legs.first)
        #expect(leg.fromCode == "PVG")
        #expect(leg.toCode == "NRT")
        #expect(leg.departure == Date(timeIntervalSince1970: 1_792_476_300))
    }
}

struct TravelTextTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    @Test func readsAFlightItinerary() throws {
        let text = """
            E-ticket itinerary
            Booking reference: XK7Q2P
            Flight MU 523  PVG → NRT
            Date 2026-10-20  Boarding 13:20  Departure 14:05
            Seat 32A  Gate D12
            """
        let trip = try #require(TravelText.parse(text, reference: Date(timeIntervalSince1970: 1_792_000_000), calendar: calendar))
        #expect(trip.mode == .flight)
        #expect(trip.bookingCode == "XK7Q2P")
        let leg = try #require(trip.legs.first)
        #expect(leg.number == "MU 523")
        #expect(leg.fromCode == "PVG")
        #expect(leg.toCode == "NRT")
        #expect(leg.seat == "32A")
        #expect(leg.departure == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14, minute: 5)))
    }

    @Test func readsAChineseRailwayTicket() throws {
        let text = """
            上海虹桥站  G1234  北京南站
            2026年10月20日 14:05开  05车12A号
            ¥553.0 二等座
            """
        let trip = try #require(TravelText.parse(text, reference: Date(timeIntervalSince1970: 1_792_000_000), calendar: calendar))
        #expect(trip.mode == .train)
        let leg = try #require(trip.legs.first)
        #expect(leg.number == "G1234")
        #expect(leg.from == "上海虹桥站")
        #expect(leg.to == "北京南站")
        #expect(leg.seat == "05车12A号")
        #expect(leg.departure == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14, minute: 5)))
    }

    @Test func ordinaryTextIsNotATrip() {
        #expect(TravelText.parse("Meeting at 14:05 on 2026-10-20 in room B12") == nil)
        #expect(TravelText.parse("Receipt\nTotal $12.50\nThank you") == nil)
    }
}

struct BookingPageTests {
    @Test func aFlightReservationIsATrip() throws {
        let json = """
            {"@context":"https://schema.org","@type":"FlightReservation","reservationNumber":"RXJ34P",
             "reservationFor":{"@type":"Flight","flightNumber":"110","airline":{"@type":"Airline","name":"United","iataCode":"UA"},
               "departureAirport":{"@type":"Airport","name":"San Francisco Airport","iataCode":"SFO"},
               "departureTime":"2027-03-04T20:15:00-08:00",
               "arrivalAirport":{"@type":"Airport","name":"John F. Kennedy International Airport","iataCode":"JFK"},
               "arrivalTime":"2027-03-05T06:30:00-05:00"}}
            """
        let structured = try #require(SchemaOrg.structuredData(fromJSONLD: [json]))
        #expect(structured.kind == .travel)
        let trip = try #require(structured.fields.trip)
        #expect(trip.bookingCode == "RXJ34P")
        let leg = try #require(trip.legs.first)
        #expect(leg.number == "UA 110")
        #expect(leg.fromCode == "SFO")
        #expect(leg.toCode == "JFK")
        #expect(leg.departureHasTime)
    }

    @Test func anEventReservationIsATicket() throws {
        let json = """
            {"@context":"http://schema.org","@type":"EventReservation","reservationNumber":"IO12345",
             "reservationFor":{"@type":"Event","name":"Foo Fighters Concert","startDate":"2027-03-06T19:30:00-08:00",
               "location":{"@type":"Place","name":"AT&T Park","address":{"@type":"PostalAddress","streetAddress":"24 Willie Mays Plaza","addressLocality":"San Francisco"}}}}
            """
        let structured = try #require(SchemaOrg.structuredData(fromJSONLD: [json]))
        #expect(structured.kind == .ticket)
        let ticket = try #require(structured.fields.ticket)
        #expect(ticket.name == "Foo Fighters Concert")
        #expect(ticket.venue == "AT&T Park")
        #expect(ticket.bookingCode == "IO12345")
    }
}

struct ProductPageTests {
    @Test func productTagsGiveAPriceWithoutSchemaData() throws {
        let html = """
            <html><head><title>Wool Coat – Example Shop</title>
            <meta property="og:title" content="Wool Coat">
            <meta property="og:site_name" content="Example Shop">
            <meta property="og:image" content="https://shop.example.com/coat.jpg">
            <meta property="product:price:amount" content="1,299.00">
            <meta property="product:price:currency" content="usd">
            </head><body></body></html>
            """
        let extraction = ItemExtractor.extraction(fromHTML: html, baseURL: URL(string: "https://shop.example.com/p/coat")!)
        let product = try #require(extraction.typedFields?.product)
        #expect(product.name == "Wool Coat")
        #expect(product.price == 1299)
        #expect(product.currency == "USD")
        #expect(product.store == "Example Shop")
        #expect(product.imageURL == "https://shop.example.com/coat.jpg")
    }

    @Test func aShoppingAppsSharedTextGivesThePrice() throws {
        let input = ExtractionInput(
            kind: .link, url: URL(string: "https://www.temu.com/goods.html?id=1"),
            text: "Women's Wool Blend Coat\nOnly $25.99 on Temu! https://www.temu.com/goods.html?id=1"
        )
        let extraction = ItemExtractor.addingSharedPrice(Extraction(), input: input)
        let product = try #require(extraction.typedFields?.product)
        #expect(product.price == 25.99)
        #expect(product.currency == "USD")
        #expect(product.name == "Women's Wool Blend Coat")
        #expect(product.origin == .text)
    }

    @Test func pricesInTheirLocalFormats() {
        #expect(PriceText.amount("1,299.00") == 1299)
        #expect(PriceText.amount("1.299,00") == 1299)
        #expect(PriceText.amount("12,50") == 12.5)
        #expect(PriceText.amount("1,299") == 1299)
        #expect(PriceText.find(in: "仅售 199元")?.0 == 199)
        #expect(PriceText.find(in: "仅售 199元")?.1 == "CNY")
        #expect(PriceText.find(in: "Price: €49,90")?.1 == "EUR")
    }
}

struct DocumentTextTests {
    @Test func readsAWordDocumentsTextAndProperties() throws {
        let body = """
            <w:document><w:body><w:p><w:r><w:t>The Future of Cities</w:t></w:r></w:p>
            <w:p><w:r><w:t xml:space="preserve">Streets for people, </w:t></w:r><w:r><w:t>not cars &amp; trucks.</w:t></w:r></w:p></w:body></w:document>
            """
        #expect(DocumentText.wordText(body) == "The Future of Cities\nStreets for people, not cars & trucks.")
        let core = """
            <cp:coreProperties><dc:title>The Future of Cities</dc:title><dc:creator>Jane Doe</dc:creator>
            <dcterms:created xsi:type="dcterms:W3CDTF">2026-09-01T08:00:00Z</dcterms:created></cp:coreProperties>
            """
        let fields = try #require(DocumentText.coreProperties(core))
        #expect(fields.headline == "The Future of Cities")
        #expect(fields.author == "Jane Doe")
        #expect(fields.publishedAt == Date(timeIntervalSince1970: 1_788_249_600))
    }
}
