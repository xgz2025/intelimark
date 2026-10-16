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

struct ProductTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    let database: LibraryDatabase
    let items: ItemRepository
    let groups: GroupRepository

    init() throws {
        database = try LibraryDatabase.inMemory()
        items = ItemRepository(database: database)
        groups = GroupRepository(database: database)
    }

    func product(_ name: String, price: Double, url: String) async throws -> String {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: url), title: name), now: now
        )
        item.typedFields = TypedFields(product: ProductFields(name: name, price: price, currency: "USD", origin: .page))
        let record = item
        try await database.writer.write { db in try record.insert(db) }
        return item.id
    }

    @Test func checkedPricesBuildAHistoryFromTheSavedPrice() async throws {
        let id = try await product("Wool Coat", price: 120, url: "https://shop.example.com/coat")
        let before = try await items.recordPrice(99, currency: "USD", forItem: id, now: now.addingTimeInterval(86_400))
        #expect(before == 120)
        let product = try #require(try await items.item(id: id)?.typedFields?.product)
        #expect(product.price == 99)
        #expect(product.originalPrice == 120)
        #expect(product.priceHistory?.map(\.price) == [120, 99])
        #expect(product.changeSinceSaved == -21)
    }

    @Test func productsDueForACheckAreTheOldestChecked() async throws {
        let coat = try await product("Wool Coat", price: 120, url: "https://shop.example.com/coat")
        let lamp = try await product("Desk Lamp", price: 40, url: "https://shop.example.com/lamp")
        try await items.recordPrice(39, currency: "USD", forItem: lamp, now: now)
        let due = try await items.productIDsToCheck(checkedBefore: now.addingTimeInterval(-3600), limit: 10)
        #expect(due == [coat])
    }

    @Test func similarProductsAreSuggestedTogetherThenJoinTheirGroup() async throws {
        let first = try await product("Women's Wool Blend Long Coat Camel", price: 120, url: "https://a.example.com/1")
        _ = try await product("Ceramic Desk Lamp", price: 40, url: "https://b.example.com/2")
        #expect(try await groups.groupSimilarProducts(itemID: first, autoAccept: false, now: now) == nil)

        let second = try await product("Long Wool Coat for Women, Camel", price: 95, url: "https://c.example.com/3")
        let suggested = try #require(try await groups.groupSimilarProducts(itemID: second, autoAccept: false, now: now))
        #expect(try await groups.group(id: suggested)?.state == .suggested)

        // Saved again: no second group.
        #expect(try await groups.groupSimilarProducts(itemID: second, autoAccept: false, now: now) == nil)

        let third = try await product("Camel Wool Coat (Women)", price: 150, url: "https://d.example.com/4")
        let joined = try await groups.groupSimilarProducts(itemID: third, autoAccept: true, now: now)
        #expect(joined == suggested)
    }

    @Test func proGetsAComparisonGroupStraightAway() async throws {
        let first = try await product("MacBook Air 13-inch M4 16GB", price: 1099, url: "https://a.example.com/1")
        _ = first
        let second = try await product("Apple MacBook Air 13 M4 16GB 512GB", price: 1199, url: "https://b.example.com/2")
        let id = try #require(try await groups.groupSimilarProducts(itemID: second, autoAccept: true, now: now))
        #expect(try await groups.group(id: id)?.state == .accepted)
    }

    @Test func namesMatchByTheirWordsOrCharacters() {
        #expect(ProductMatching.similarity("Wool Coat Camel", "Camel wool coat") == 1)
        #expect(ProductMatching.similarity("Wool Coat", "Desk Lamp") == 0)
        #expect(ProductMatching.similarity("女士羊毛大衣 驼色", "驼色羊毛大衣") >= ProductMatching.threshold)
    }

    func record(_ name: String, price: Double? = nil, brand: String? = nil, url: String = "https://shop.example.com/p") -> ItemRecord {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: url), title: name), now: now
        )
        item.typedFields = TypedFields(product: ProductFields(name: name, brand: brand, price: price, currency: "USD"))
        return item
    }

    @Test func theSameProductMatchesAndOthersDont() {
        // Model numbers decide.
        #expect(ProductMatching.matches(record("Sony WH-1000XM5 Wireless Headphones"), record("WH-1000XM5 Noise Cancelling Headphones, Black")))
        #expect(!ProductMatching.matches(record("Sony WH-1000XM5 Wireless Headphones"), record("Sony WH-1000XM4 Wireless Headphones")))
        // Sizes aren't model numbers.
        #expect(ProductMatching.matches(record("MacBook Air 13-inch M4 16GB"), record("Apple MacBook Air 13 M4 16GB 512GB")))
        // Prices far apart.
        #expect(!ProductMatching.matches(record("Long Wool Coat Camel", price: 30), record("Camel Long Wool Coat", price: 400)))
        // Other brands.
        #expect(!ProductMatching.matches(
            record("Running Shoes Pegasus 41", brand: "Nike"), record("Running Shoes Ultraboost", brand: "Adidas")
        ))
        // One word in common isn't enough; shop words don't count.
        #expect(!ProductMatching.matches(record("Amazon Essentials Wool Sweater"), record("SHEIN Wool Socks")))
        // The same link, whatever the names.
        #expect(ProductMatching.matches(
            record("Coat", url: "https://www.amazon.com/dp/B0ABC12345?tag=x"), record("Something else", url: "https://amazon.com/x/dp/B0ABC12345")
        ))
    }

    @Test func productLinksMatchWhateverTheirTracking() {
        let amazon = ProductURL.key(URL(string: "https://www.amazon.com/Wool-Coat/dp/B0ABC12345/ref=sr_1_3?tag=x"))
        #expect(amazon == ProductURL.key(URL(string: "https://amazon.com/dp/B0ABC12345?psc=1")))
        #expect(amazon != ProductURL.key(URL(string: "https://amazon.co.jp/dp/B0ABC12345")))
        let temu = ProductURL.key(URL(string: "https://www.temu.com/goods.html?goods_id=601&_x_sessn_id=abc&refer_page_name=home"))
        #expect(temu == "temu.com/goods.html?goods_id=601")
        #expect(ProductURL.key(URL(string: "https://shop.example.com/products/coat/?utm_source=ig"))
            == ProductURL.key(URL(string: "https://shop.example.com/products/coat")))
    }

    @Test func aTargetIsAnnouncedOnceWhenReached() {
        #expect(PriceAlert.notice(for: .dropped(from: 320, to: 289, currency: "CNY"), target: 299, includesDrops: false)
            == .reachedTarget(price: 289, target: 299))
        // Already under it: said before.
        #expect(PriceAlert.notice(for: .dropped(from: 289, to: 279, currency: "CNY"), target: 299, includesDrops: false) == nil)
        #expect(PriceAlert.notice(for: .unchanged(289), target: 299, includesDrops: true) == nil)
        // Drops are told to Pro.
        #expect(PriceAlert.notice(for: .dropped(from: 400, to: 350, currency: "CNY"), target: 299, includesDrops: true)
            == .dropped(from: 400, to: 350))
        #expect(PriceAlert.notice(for: .dropped(from: 400, to: 350, currency: "CNY"), target: nil, includesDrops: false) == nil)
    }

    @Test func aTargetPriceIsKeptAndCleared() async throws {
        let id = try await product("Wool Coat", price: 120, url: "https://shop.example.com/coat")
        try await items.setTargetPrice(99, forItem: id)
        #expect(try await items.item(id: id)?.targetPrice == 99)
        try await items.setTargetPrice(0, forItem: id)
        #expect(try await items.item(id: id)?.targetPrice == nil)
    }
}

