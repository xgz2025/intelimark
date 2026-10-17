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

struct ProductPriceTests {
    /// The price script runs in three places; they must read prices the same way.
    @Test func thePriceScriptIsTheSameEverywhere() throws {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent()      // ExtractionTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // NextmarkKit
            .deletingLastPathComponent()      // Packages
            .deletingLastPathComponent()      // repository
        func block(_ path: String) throws -> String {
            let text = try String(contentsOf: repository.appending(path: path), encoding: .utf8)
            let start = try #require(text.range(of: "// BEGIN laterwisePrice"))
            let end = try #require(text.range(of: "// END laterwisePrice"))
            return String(text[start.lowerBound..<end.upperBound])
        }
        let canonical = try block("Extensions/Shared/ProductPrice.js")
        #expect(try block("Extensions/Share/Shared/PageCapture.js") == canonical)
        #expect(try block("Extensions/Safari/Resources/content.js") == canonical)
    }

    @Test func aShownPriceMakesAProductWhenNoTagStatesOne() throws {
        let fromElement = try #require(ProductPage.product(
            tags: ["laterwise:price": "$1,299.99", "laterwise:priceSource": "selector"],
            title: "Wool Coat", description: nil, imageURL: nil, siteName: "Amazon"
        ))
        #expect(fromElement.price == 1299.99)
        #expect(fromElement.currency == "USD")
        #expect(fromElement.origin == .page)

        let fromLayout = try #require(ProductPage.product(
            tags: ["laterwise:price": "29,90 €", "laterwise:priceSource": "visible"],
            title: "Coat", description: nil, imageURL: nil, siteName: nil
        ))
        #expect(fromLayout.price == 29.9)
        #expect(fromLayout.currency == "EUR")
        #expect(fromLayout.origin == .shown)

        // A tag that states the price wins over what the page shows.
        let tagged = try #require(ProductPage.product(
            tags: ["product:price:amount": "25.00", "product:price:currency": "USD", "laterwise:price": "$19.99"],
            title: "Coat", description: nil, imageURL: nil, siteName: nil
        ))
        #expect(tagged.price == 25)
    }

    @Test func readsThePriceAShopKeepsInItsScripts() throws {
        let target = """
            <html><head><title>Wool Coat : Target</title></head><body><div id="root"></div>
            <script>window.__TGT_DATA__ = JSON.parse("{\\"product\\":{\\"price\\":{\\"current_retail\\":49.99,\\"formatted_current_price\\":\\"$49.99\\"}}}")</script>
            </body></html>
            """
        let product = try #require(
            ItemExtractor.extraction(fromHTML: target, baseURL: URL(string: "https://www.target.com/p/coat/-/A-123")!).typedFields?.product
        )
        #expect(product.price == 49.99)
        #expect(product.currency == "USD")
        #expect(product.origin == .page)

        let shein = #"<script>var productIntroData = {"retailPrice":{"amountWithSymbol":"$20.00"},"salePrice":{"amount":"12.49","amountWithSymbol":"\u002412.49"}}</script>"#
        let read = try #require(ProductPage.embeddedPrice(inHTML: shein, host: "us.shein.com"))
        #expect(read.price == 12.49)
        // Another shop's page isn't read for these keys.
        #expect(ProductPage.embeddedPrice(inHTML: shein, host: "example.com") == nil)
    }

    @Test func readsWhatThePriceScriptReturns() throws {
        let price = try #require(ShownPrice(script: ["price": "US$15.49", "currency": NSNull(), "source": "visible"] as [String: Any]))
        #expect(price == ShownPrice(price: 15.49, currency: "USD", origin: .shown))
        let coded = try #require(ShownPrice(script: ["price": "299", "currency": "cny", "source": "selector"]))
        #expect(coded == ShownPrice(price: 299, currency: "CNY", origin: .page))
        #expect(ShownPrice(script: nil) == nil)
        #expect(ShownPrice(script: ["price": "Free"]) == nil)
    }

    @Test func listsEveryPriceInAScreenshotOnce() {
        let text = """
            Wool Coat
            List Price: $159.99
            Now $129.99 Save $30.00
            $129.99
            Ships in 2 days
            """
        let mentions = PriceText.all(in: text)
        #expect(mentions.map(\.price) == [159.99, 129.99, 30])
        #expect(mentions.first?.line == "List Price: $159.99")
        #expect(mentions.allSatisfy { $0.currency == "USD" })
        #expect(PriceText.all(in: "¥199 到手价 159元").map(\.price) == [199, 159])
    }
}
