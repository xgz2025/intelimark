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
import Capture
@testable import Library

struct ItemCardTests {
    func item(_ kind: ItemKind, url: String? = nil, title: String? = nil) -> ItemRecord {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: url.flatMap { URL(string: $0) }, title: title)
        )
        item.kind = kind
        return item
    }

    @Test func aReceiptShowsItsMerchantAndTotal() {
        var receipt = item(.image)
        receipt.aiTitle = "Coffee receipt"
        receipt.semanticKind = .receipt
        receipt.typedFields = TypedFields(receipt: ReceiptFields(merchant: "Blue Bottle Coffee", total: 10.61, currency: "USD"))
        let card = receipt.card
        #expect(card.style == .receipt)
        #expect(card.title == "Blue Bottle Coffee")
        #expect(card.figure == 10.61.formatted(.currency(code: "USD")))
        #expect(card.snippet == nil)
    }

    @Test func aPageReadsLikeASearchResult() {
        var page = item(.link, url: "https://www.example.com/recipes/ramen-guide?ref=1", title: "The Ramen Guide")
        page.summary = "Everything about broth, noodles and toppings."
        let card = page.card
        #expect(card.style == .web)
        #expect(card.source == "example.com › recipes › ramen-guide")
        #expect(card.title == "The Ramen Guide")
        #expect(card.snippet == "Everything about broth, noodles and toppings.")
    }

    @Test func aDocumentShowsItsTitleAndAuthor() {
        var document = item(.pdf, title: "draft-final-2.pdf")
        document.summary = "A proposal for the new library."
        document.typedFields = TypedFields(article: ArticleFields(headline: "Library Proposal", author: "Jane Doe"))
        let card = document.card
        #expect(card.style == .document)
        #expect(card.title == "Library Proposal")
        #expect(card.byline == "Jane Doe")
        #expect(card.snippet == "A proposal for the new library.")
    }

    @Test func aPhotoShowsWhereItWasTaken() {
        var photo = item(.image)
        photo.aiTitle = "Sunset over the bay"
        photo.imageDescription = "The sun setting behind the Golden Gate Bridge."
        let taken = Date(timeIntervalSince1970: 1_791_020_527)
        photo.typedFields = TypedFields(photo: PhotoFields(takenAt: taken, latitude: 37.8, longitude: -122.4, placeName: "San Francisco"))
        let card = photo.card
        #expect(card.style == .photo)
        #expect(card.byline == "San Francisco · " + taken.formatted(date: .abbreviated, time: .omitted))
        #expect(card.snippet == "The sun setting behind the Golden Gate Bridge.")
    }

    @Test func theUsersTitleAlwaysWins() {
        var document = item(.pdf, title: "file.pdf")
        document.userTitle = "My contract"
        document.typedFields = TypedFields(article: ArticleFields(headline: "Agreement"))
        #expect(document.card.title == "My contract")
    }

    @Test func aReceiptIsDatedByItsOwnDateNotTheDayItWasSaved() {
        var receipt = item(.image)
        receipt.semanticKind = .receipt
        receipt.typedFields = TypedFields(receipt: ReceiptFields(merchant: "Blue Bottle Coffee", total: 10.61, currency: "USD"))
        #expect(receipt.card.byline == nil)
        let printed = Date(timeIntervalSince1970: 1_791_020_527)
        receipt.typedFields?.receipt?.purchasedAt = printed
        #expect(receipt.card.byline == printed.formatted(date: .abbreviated, time: .omitted))
    }

    @Test func factsSayWhereTheyCameFrom() {
        var photo = item(.image)
        let taken = Date(timeIntervalSince1970: 1_791_020_527)
        photo.typedFields = TypedFields(photo: PhotoFields(takenAt: taken, latitude: 35.66, longitude: 139.7, placeName: "Shibuya, Tokyo"))
        let facts = photo.facts
        #expect(facts.map(\.label) == [.taken, .location, .saved])
        #expect(facts[0].source == .photoMetadata)
        #expect(facts[0].value == .date(taken, hasTime: true))
        #expect(facts[1].source == .photoLocation)
        #expect(facts[2].source == .capture(.shareSheet))

        var pdf = item(.pdf)
        pdf.typedFields = TypedFields(article: ArticleFields(author: "Jane Doe", publishedAt: taken))
        #expect(pdf.facts.map(\.label) == [.author, .created, .saved])
        #expect(pdf.facts[0].source == .documentInfo)
    }

    @Test func placesTheItemAlreadyStatesArentRepeatedAsFound() {
        var photo = item(.image)
        photo.typedFields = TypedFields(photo: PhotoFields(placeName: "Shibuya, Tokyo"))
        photo.places = [
            ItemPlace(name: "Shibuya, Tokyo", source: .structured),
            ItemPlace(name: "shibuya, tokyo", source: .model),
            ItemPlace(name: "Ginza", source: .detector),
        ]
        #expect(photo.inferredPlaces.map(\.name) == ["Ginza"])
    }

    @Test func aTripReadsAsItsRouteAndDeparture() {
        var trip = item(.image)
        let departure = Date(timeIntervalSince1970: 1_792_500_000)
        trip.typedFields = TypedFields(trip: TripFields(mode: .flight, legs: [
            TripLeg(carrier: "MU", number: "MU 523", from: "Shanghai", fromCode: "PVG", to: "Tokyo", toCode: "NRT",
                    departure: departure, terminal: "1", seat: "32A"),
        ]))
        #expect(trip.saveType == .travel)
        let card = trip.card
        #expect(card.style == .travel)
        #expect(card.title == "Shanghai (PVG) → Tokyo (NRT)")
        #expect(card.byline?.hasPrefix("MU 523 · ") == true)
        #expect(trip.departures.first?.date == departure)
    }

    @Test func aShowReadsAsItsNameDateAndVenue() {
        var show = item(.link, url: "https://tickets.example.com/order/1")
        let start = Date(timeIntervalSince1970: 1_792_500_000)
        show.typedFields = TypedFields(ticket: TicketFields(name: "Swan Lake", startDate: start, venue: "Royal Opera House"))
        #expect(show.saveType == .show)
        let card = show.card
        #expect(card.title == "Swan Lake")
        #expect(card.byline?.hasSuffix("Royal Opera House") == true)
        #expect(show.showStart?.date == start)
    }

    @Test func aProductShowsItsPriceAndChangeSinceSaved() {
        var coat = item(.link, url: "https://shop.example.com/products/wool-coat")
        var product = ProductFields(name: "Wool Coat", price: 120, currency: "USD", store: "Example Shop")
        product.record(price: 120, currency: "USD", at: Date(timeIntervalSince1970: 1_790_000_000))
        product.record(price: 95, currency: "USD", at: Date(timeIntervalSince1970: 1_790_200_000))
        coat.typedFields = TypedFields(product: product)
        let card = coat.card
        #expect(card.style == .product)
        #expect(card.figure == 95.0.formatted(.currency(code: "USD")))
        #expect(card.isDrop)
        #expect(card.change == "↓ " + 25.0.formatted(.currency(code: "USD")))
        #expect(product.priceHistory?.map(\.price) == [120, 95])
        #expect(product.lowestPrice == 95)
    }
}

