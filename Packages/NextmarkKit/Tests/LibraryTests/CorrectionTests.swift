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
import GRDB
import Model
@testable import Library

struct CorrectionTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    let database: LibraryDatabase
    let items: ItemRepository

    init() throws {
        database = try LibraryDatabase.inMemory()
        items = ItemRepository(database: database)
    }

    func save(_ fields: TypedFields) async throws -> String {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://example.com/a"), title: "Saved"),
            now: now
        )
        item.typedFields = fields
        let record = item
        try await database.writer.write { db in try record.insert(db) }
        return item.id
    }

    static let readTrip = TripFields(mode: .flight, legs: [TripLeg(number: "MU 523", from: "Shanghai", to: "Tokyo")], origin: .model)

    @Test func uncertainFieldsAskOnceAndAreKeptOnceConfirmed() async throws {
        let id = try await save(TypedFields(trip: Self.readTrip))
        #expect(try await items.item(id: id)?.needsConfirmation == true)
        try await items.correct(.confirm, forItem: id, now: now)
        let confirmed = try #require(try await items.item(id: id))
        #expect(confirmed.needsConfirmation == false)
        #expect(confirmed.typedFields?.trip?.origin == .user)

        // Read again, the confirmed trip stays as it was.
        let reread = Extraction(structured: StructuredData(kind: .travel, fields: TypedFields(trip: TripFields(
            mode: .flight, legs: [TripLeg(number: "MU 5", from: "Shanghai", to: "Osaka")], origin: .text
        ))))
        try await items.applyExtraction(reread, toItem: id, version: 1, now: now)
        #expect(try await items.item(id: id)?.typedFields?.trip?.legs.first?.to == "Tokyo")
    }

    @Test func exactSourcesDontAsk() async throws {
        var trip = Self.readTrip
        trip.origin = .walletPass
        let id = try await save(TypedFields(trip: trip))
        #expect(try await items.item(id: id)?.needsConfirmation == false)
    }

    @Test func notAReceiptIsntGuessedAgain() async throws {
        let id = try await save(TypedFields(receipt: ReceiptFields(merchant: "Cafe", total: 12, currency: "USD", origin: .text)))
        #expect(try await items.item(id: id)?.saveType == .receipt)
        try await items.correct(.reject(.receipt), forItem: id, now: now)
        #expect(try await items.item(id: id)?.saveType == .link)
        #expect(try await items.item(id: id)?.typedFields?.receipt == nil)

        let reread = Extraction(structured: StructuredData(kind: .receipt, fields: TypedFields(receipt: ReceiptFields(total: 12))))
        try await items.applyExtraction(reread, toItem: id, version: 1, now: now)
        let item = try #require(try await items.item(id: id))
        #expect(item.saveType == .link)
        #expect(item.typedFields?.receipt == nil)
    }

    @Test func anEditedTripMovesItsDeparture() async throws {
        let id = try await save(TypedFields(trip: Self.readTrip))
        let departure = now.addingTimeInterval(86_400 * 3)
        var trip = Self.readTrip
        trip.legs[0].departure = departure
        try await items.correct(.trip(trip), forItem: id, now: now)
        let item = try #require(try await items.item(id: id))
        #expect(item.typedFields?.trip?.origin == .user)
        #expect(item.departures.map(\.date) == [departure])
    }

    @Test func aCorrectedPriceReplacesTheMisreadOne() async throws {
        let id = try await save(TypedFields(product: ProductFields(name: "Coat", price: 5, currency: "USD", origin: .shown)))
        try await items.correct(.product(name: "Wool Coat", price: 129.99, currency: "USD", store: "Amazon"), forItem: id, now: now)
        let product = try #require(try await items.item(id: id)?.typedFields?.product)
        #expect(product.price == 129.99)
        #expect(product.originalPrice == 129.99)
        #expect(product.changeSinceSaved == nil)
        #expect(product.origin == .user)
        #expect(product.name == "Wool Coat")
    }

    @Test func aPageWithoutAPriceKeepsTheProduct() async throws {
        let id = try await save(TypedFields())
        try await items.recordPrice(49, currency: "USD", origin: .shown, forItem: id, now: now)
        #expect(try await items.item(id: id)?.typedFields?.product?.origin == .shown)
        try await items.applyExtraction(Extraction(title: "Coat"), toItem: id, version: 1, now: now)
        #expect(try await items.item(id: id)?.typedFields?.product?.price == 49)
    }
}

struct FoundInTextTests {
    @Test func datesWithoutAMeaningArentListedAndTheRestReadInContext() {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: nil, title: "Note"),
            now: Date(timeIntervalSince1970: 1_791_000_000)
        )
        item.contentText = "Our autumn exhibition runs Oct 21 - Oct 26 at the gallery. Please apply by Oct 10 to take part in the opening."
        let when = Date(timeIntervalSince1970: 1_791_500_000)
        item.dates = [
            ItemDate(date: when, hasTime: false, role: .mentioned, evidence: "Oct 21 - Oct 26", source: .detector),
            ItemDate(date: when, hasTime: false, role: .deadline, evidence: "apply by Oct 10", source: .model),
        ]
        #expect(item.inferredDates.map(\.role) == [.deadline])
        let context = item.context(of: "apply by Oct 10", radius: 12)
        #expect(context == "…gallery. Please apply by Oct 10 to take part…")
    }
}
