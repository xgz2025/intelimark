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

    private let fetcher: any PageFetcher
    private let repository: ItemRepository

    public init(database: LibraryDatabase, fetcher: any PageFetcher = URLSessionPageFetcher()) {
        self.fetcher = fetcher
        repository = ItemRepository(database: database)
    }

    public func check(_ itemID: String, now: Date = Date()) async -> Outcome {
        guard let item = try? await repository.item(id: itemID),
              let url = item.canonicalURL.flatMap({ URL(string: $0) }), url.scheme == "https" || url.scheme == "http",
              let resource = try? await fetcher.fetch(url), (200..<300).contains(resource.statusCode),
              let html = resource.text,
              let product = ItemExtractor.extraction(fromHTML: html, baseURL: resource.finalURL).typedFields?.product,
              let price = product.price
        else {
            try? await repository.markPriceChecked(forItem: itemID, now: now)
            return .unavailable
        }
        // Another currency than before (the shop showed another region's page) starts over.
        let previousCurrency = (try? await repository.item(id: itemID))?.typedFields?.product?.currency
        guard let before = try? await repository.recordPrice(price, currency: product.currency, forItem: itemID, now: now) else {
            return .found(price)
        }
        if let previousCurrency, let currency = product.currency, previousCurrency != currency { return .found(price) }
        if price < before - 0.005 { return .dropped(from: before, to: price, currency: product.currency) }
        if price > before + 0.005 { return .rose(from: before, to: price, currency: product.currency) }
        return .unchanged(price)
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
