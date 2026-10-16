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
import Library
import Extraction

/// Check Price (Docs/save_types.md): reads a product's page again and records its
/// price. Only the page is requested; nothing about the person is sent.
public struct PriceChecker: Sendable {
    public typealias Outcome = PriceCheckOutcome
    /// Loads a page in a browser engine and reads what it shows once its scripts have
    /// run (`WebPagePriceReader` in the app).
    public typealias Renderer = @Sendable (URL) async -> RenderedPage?

    private let fetcher: any PageFetcher
    private let repository: ItemRepository
    private let renderer: Renderer?

    public init(database: LibraryDatabase, fetcher: any PageFetcher = URLSessionPageFetcher(), renderer: Renderer? = nil) {
        self.fetcher = fetcher
        self.renderer = renderer
        repository = ItemRepository(database: database)
    }

    public func check(_ itemID: String, now: Date = Date()) async -> Outcome {
        guard let item = try? await repository.item(id: itemID),
              let url = item.canonicalURL.flatMap({ URL(string: $0) }), url.scheme == "https" || url.scheme == "http",
              let read = await price(at: url)
        else {
            try? await repository.markPriceChecked(forItem: itemID, now: now)
            return .unavailable
        }
        let price = read.price
        // Another currency than before (the shop showed another region's page) starts over.
        let previousCurrency = item.typedFields?.product?.currency
        guard let before = try? await repository.recordPrice(
            price, currency: read.currency, origin: read.origin, forItem: itemID, now: now
        ) else {
            return .found(price)
        }
        if let previousCurrency, let currency = read.currency, previousCurrency != currency { return .found(price) }
        if price < before - 0.005 { return .dropped(from: before, to: price, currency: read.currency) }
        if price > before + 0.005 { return .rose(from: before, to: price, currency: read.currency) }
        return .unchanged(price)
    }

    /// The page's price: from the page as fetched when it states one (its tags or
    /// schema.org data), else as a browser shows it (Amazon, Target, Shein…).
    func price(at url: URL) async -> ShownPrice? {
        if let resource = try? await fetcher.fetch(url), (200..<300).contains(resource.statusCode), let html = resource.text,
           let product = ItemExtractor.extraction(fromHTML: html, baseURL: resource.finalURL).typedFields?.product,
           let price = product.price {
            return ShownPrice(price: price, currency: product.currency, origin: product.origin ?? .page)
        }
        return await renderer?(url)?.price
    }

    /// Several products, a few at a time.
    public func check(_ itemIDs: [String], now: Date = Date()) async -> [String: Outcome] {
        var outcomes: [String: Outcome] = [:]
        for chunk in stride(from: 0, to: itemIDs.count, by: 4).map({ Array(itemIDs[$0..<min($0 + 4, itemIDs.count)]) }) {
            await withTaskGroup(of: (String, Outcome).self) { group in
                for id in chunk {
                    group.addTask { (id, await check(id, now: now)) }
                }
                for await (id, outcome) in group {
                    outcomes[id] = outcome
                }
            }
        }
        return outcomes
    }
}
