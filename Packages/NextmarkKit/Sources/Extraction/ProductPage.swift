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

/// A shop's product, from the tags many shops add for link previews
/// (`product:price:amount`, `og:price:amount`, microdata `price`) when the page has
/// no schema.org product, and from the text a shopping app shares.
public enum ProductPage {
    /// Hosts of shops: a link to one with a price in its shared text is a product.
    static let shopHosts = [
        "amazon.", "a.co", "amzn.", "ebay.", "temu.", "shein.", "aliexpress.", "alibaba.", "taobao.", "tmall.",
        "jd.com", "3.cn", "yangkeduo.", "pinduoduo.", "etsy.", "walmart.", "target.com", "bestbuy.", "costco.",
        "ikea.", "zara.", "uniqlo.", "hm.com", "nike.", "adidas.", "apple.com", "myshopify.com", "shopify.",
        "rakuten.", "mercari.", "zalando.", "asos.", "vip.com", "dangdang.", "suning.", "xiaohongshu.", "xhslink.",
    ]

    static func isShop(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return shopHosts.contains { host.contains($0) }
    }

    /// The tags' product, when they state a price.
    static func product(tags: [String: String], title: String?, description: String?, imageURL: String?, siteName: String?) -> ProductFields? {
        let lowered = Dictionary(tags.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let amount = lowered["product:price:amount"] ?? lowered["og:price:amount"] ?? lowered["itemprop:price"] ?? lowered["price"]
        guard let price = amount.flatMap(PriceText.amount) else { return nil }
        let currency = lowered["product:price:currency"] ?? lowered["og:price:currency"]
            ?? lowered["itemprop:pricecurrency"] ?? lowered["pricecurrency"]
        return ProductFields(
            name: lowered["og:title"] ?? title,
            brand: lowered["product:brand"],
            price: price,
            currency: currency?.uppercased(),
            availability: lowered["product:availability"],
            description: (lowered["og:description"] ?? description).map { String($0.prefix(500)) },
            imageURL: lowered["og:image"] ?? imageURL,
            store: lowered["og:site_name"] ?? siteName,
            origin: .page
        )
    }

    /// A page's product, its gaps filled from the tags: a schema.org product often has
    /// no image or shop name; a page without one may still state its price.
    static func complete(_ structured: StructuredData?, with tagged: ProductFields?) -> StructuredData? {
        guard let tagged else { return structured }
        guard let structured else { return StructuredData(kind: .product, fields: TypedFields(product: tagged)) }
        guard structured.kind == .product, var product = structured.fields.product else { return structured }
        product.price = product.price ?? tagged.price
        product.currency = product.currency ?? tagged.currency
        product.description = product.description ?? tagged.description
        product.imageURL = product.imageURL ?? tagged.imageURL
        product.store = product.store ?? tagged.store
        product.brand = product.brand ?? tagged.brand
        var completed = structured
        completed.fields.product = product
        return completed
    }

    /// What a shopping app shares ("Wool Coat – $89.99 https://…"): a product named by
    /// its first line, at the price in the text.
    static func product(sharedText text: String, url: URL?, siteName: String?) -> ProductFields? {
        guard isShop(url), let (price, currency) = PriceText.find(in: text) else { return nil }
        let name = text.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 3 }
        return ProductFields(name: name.map { String($0.prefix(140)) }, price: price, currency: currency, store: siteName, origin: .text)
    }
}

/// Prices written in text: "$1,299.00", "1.299,00 €", "¥199", "199元", "US$ 25".
public enum PriceText {
    /// "1,299.00" → 1299, "1.299,00" → 1299, "12,50" → 12.5, "1299" → 1299.
    public static func amount(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !digits.isEmpty else { return nil }
        let lastDot = digits.lastIndex(of: ".")
        let lastComma = digits.lastIndex(of: ",")
        var normalized: String
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            // Whichever comes last is the decimal mark.
            normalized = dot > comma ? digits.replacingOccurrences(of: ",", with: "")
                : digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        case let (nil, comma?):
            // "12,50" is a decimal comma; "1,299" a thousands separator.
            let decimals = digits.distance(from: comma, to: digits.endIndex) - 1
            normalized = decimals == 3 ? digits.replacingOccurrences(of: ",", with: "") : digits.replacingOccurrences(of: ",", with: ".")
        case let (dot?, nil):
            let decimals = digits.distance(from: dot, to: digits.endIndex) - 1
            let dots = digits.filter { $0 == "." }.count
            normalized = dots > 1 || decimals == 3 ? digits.replacingOccurrences(of: ".", with: "") : digits
        default:
            normalized = digits
        }
        guard let value = Double(normalized), value > 0, value < 10_000_000 else { return nil }
        return value
    }

    /// The first price in `text` with its currency.
    public static func find(in text: String) -> (Double, String?)? {
        let before = #/(US\$|C\$|A\$|HK\$|S\$|NT\$|R\$|\$|€|£|¥|￥|₩|₹|RMB|CNY|USD|EUR|GBP|JPY|HKD|AUD|CAD)\s?(\d[\d.,]*\d|\d)/#
        let after = #/(\d[\d.,]*\d|\d)\s?(元|円|€|USD|EUR|GBP|CNY|RMB)/#
        if let match = text.firstMatch(of: before), let value = amount(String(match.output.2)) {
            return (value, currency(String(match.output.1), in: text))
        }
        if let match = text.firstMatch(of: after), let value = amount(String(match.output.1)) {
            return (value, currency(String(match.output.2), in: text))
        }
        return nil
    }

    static func currency(_ symbol: String, in text: String) -> String? {
        switch symbol {
        case "US$", "USD": "USD"
        case "C$", "CAD": "CAD"
        case "A$", "AUD": "AUD"
        case "HK$", "HKD": "HKD"
        case "S$": "SGD"
        case "NT$": "TWD"
        case "R$": "BRL"
        case "€", "EUR": "EUR"
        case "£", "GBP": "GBP"
        case "₩": "KRW"
        case "₹": "INR"
        case "元", "RMB", "CNY", "￥": "CNY"
        case "円", "JPY": "JPY"
        // Yuan or yen: the words around it say which, else where the person is.
        case "¥": ReceiptParser.currencyCode(in: text) ?? "JPY"
        // A bare "$" is the person's own dollar (Canada, Australia…), else the US one.
        case "$": dollarCurrency
        default: nil
        }
    }

    static var dollarCurrency: String {
        let local = Locale.current.currency?.identifier ?? "USD"
        return ["CAD", "AUD", "NZD", "HKD", "SGD", "TWD"].contains(local) ? local : "USD"
    }
}
