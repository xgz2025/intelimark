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

    public static func isShop(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return shopHosts.contains { host.contains($0) }
    }

    /// The tags' product, when they state a price.
    static func product(tags: [String: String], title: String?, description: String?, imageURL: String?, siteName: String?) -> ProductFields? {
        let lowered = Dictionary(tags.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let amount = lowered["product:price:amount"] ?? lowered["og:price:amount"] ?? lowered["itemprop:price"] ?? lowered["price"]
        var currency = lowered["product:price:currency"] ?? lowered["og:price:currency"]
            ?? lowered["itemprop:pricecurrency"] ?? lowered["pricecurrency"]
        var origin = FieldOrigin.page
        var price = amount.flatMap(PriceText.amount)
        if price == nil, let shown = lowered["laterwise:price"], let read = shownPrice(shown, currency: lowered["laterwise:currency"]) {
            // No tag states it: the price as the page shows it (ProductPrice.js), read
            // by the shop's own price element, or else picked out of the layout.
            price = read.price
            currency = currency ?? read.currency
            origin = lowered["laterwise:pricesource"] == "selector" ? .page : .shown
        }
        guard let price else { return nil }
        return ProductFields(
            name: lowered["og:title"] ?? title,
            brand: lowered["product:brand"],
            price: price,
            currency: currency?.uppercased(),
            availability: lowered["product:availability"],
            description: (lowered["og:description"] ?? description).map { String($0.prefix(500)) },
            imageURL: lowered["og:image"] ?? imageURL,
            store: lowered["og:site_name"] ?? siteName,
            origin: origin
        )
    }

    /// The price a shop keeps in its page's scripts (Target, Shein, Walmart): there in the
    /// HTML even before the page shows it. The same patterns as ProductPrice.js.
    static func embeddedPrice(inHTML html: String, host: String?) -> (price: Double, currency: String?)? {
        guard let host = host?.lowercased() else { return nil }
        var patterns: [(Regex<(Substring, Substring)>, String?)] = []
        // Quotes may be escaped (Target's data is JSON inside a JSON string), and the
        // price may be too (a "\u0024" for the dollar sign).
        if host == "target.com" || host.hasSuffix(".target.com") {
            patterns = [
                (#/\\?"formatted_current_price\\?"\s*:\s*\\?"((?:[^"\\]|\\u[0-9a-fA-F]{4}){1,40})/#, "USD"),
                (#/\\?"current_retail\\?"\s*:\s*([\d.]{1,12})/#, "USD"),
            ]
        } else if host.contains("shein.") {
            patterns = [
                (#/\\?"salePrice\\?"\s*:\s*\{[^{}]{0,400}?\\?"amountWithSymbol\\?"\s*:\s*\\?"((?:[^"\\]|\\u[0-9a-fA-F]{4}){1,40})/#, nil),
            ]
        } else if host.contains("walmart.") {
            patterns = [
                (#/\\?"currentPrice\\?"\s*:\s*\{[^{}]{0,400}?\\?"priceString\\?"\s*:\s*\\?"((?:[^"\\]|\\u[0-9a-fA-F]{4}){1,40})/#, nil),
            ]
        }
        for (pattern, code) in patterns {
            guard let match = html.firstMatch(of: pattern) else { continue }
            let text = unescaped(String(match.output.1))
            if let read = shownPrice(text, currency: code) { return read }
        }
        return nil
    }

    /// "\u002412.49" → "$12.49".
    static func unescaped(_ text: String) -> String {
        text.replacing(#/\\u([0-9a-fA-F]{4})/#) { match in
            UInt32(match.output.1, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
        }
    }

    /// "$1,299.00", "US$25", "29.99": a shown price and its currency.
    static func shownPrice(_ text: String, currency: String?) -> (price: Double, currency: String?)? {
        let code = currency.flatMap { $0.count == 3 ? $0.uppercased() : nil }
        if let (price, found) = PriceText.find(in: text) { return (price, code ?? found) }
        return PriceText.amount(text).map { ($0, code) }
    }

    /// A page's product, its gaps filled from the tags: a schema.org product often has
    /// no image or shop name; a page without one may still state its price.
    static func complete(_ structured: StructuredData?, with tagged: ProductFields?) -> StructuredData? {
        guard let tagged else { return structured }
        guard let structured else { return StructuredData(kind: .product, fields: TypedFields(product: tagged)) }
        guard structured.kind == .product, var product = structured.fields.product else { return structured }
        if product.price == nil, let price = tagged.price {
            product.price = price
            product.currency = product.currency ?? tagged.currency
            product.origin = tagged.origin
        }
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

    /// A price written in text, with the line it's on.
    public struct Mention: Sendable, Hashable {
        public var price: Double
        public var currency: String?
        /// The line it was read from: "Now $29.99", "List price: $39.99".
        public var line: String
    }

    /// Every price in `text` that names its currency, in reading order, each once: what a
    /// screenshot of a shop's page says, for the person to pick the real one.
    public static func all(in text: String, limit: Int = 8) -> [Mention] {
        var mentions: [Mention] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            var rest = Substring(line)
            while let (price, currency, range) = next(in: rest, context: text) {
                if let price, !mentions.contains(where: { $0.price == price && $0.currency == currency }) {
                    mentions.append(Mention(price: price, currency: currency, line: String(line.prefix(80))))
                    if mentions.count == limit { return mentions }
                }
                rest = rest[range.upperBound...]
            }
        }
        return mentions
    }

    /// The next amount with a currency in `text`, and where it ends; its price is nil
    /// when the digits aren't one.
    static func next(in text: Substring, context: String) -> (Double?, String?, Range<Substring.Index>)? {
        let before = #/(US\$|C\$|A\$|HK\$|S\$|NT\$|R\$|\$|€|£|¥|￥|₩|₹|RMB|CNY|USD|EUR|GBP|JPY|HKD|AUD|CAD)\s?(\d[\d.,]*\d|\d)/#
        let after = #/(\d[\d.,]*\d|\d)\s?(元|円|€|USD|EUR|GBP|CNY|RMB)/#
        let early = text.firstMatch(of: before)
        let late = text.firstMatch(of: after)
        if let early, late.map({ early.range.lowerBound <= $0.range.lowerBound }) ?? true {
            return (amount(String(early.output.2)), currency(String(early.output.1), in: context), early.range)
        }
        if let late {
            return (amount(String(late.output.1)), currency(String(late.output.2), in: context), late.range)
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

/// A product's price as its page showed it once the page's scripts ran: read by
/// `laterwisePrice()` (Extensions/Shared/ProductPrice.js) in the app's own WebKit page.
public struct ShownPrice: Sendable, Equatable {
    public var price: Double
    public var currency: String?
    /// `.page` when read from the shop's own price element; `.shown` when picked out
    /// of the layout (worth a "Correct?").
    public var origin: FieldOrigin

    public init(price: Double, currency: String?, origin: FieldOrigin) {
        self.price = price
        self.currency = currency
        self.origin = origin
    }

    /// What `laterwisePrice()` returned: `{price, currency, source}`, or null.
    public init?(script result: Any?) {
        guard let result = result as? [String: Any], let text = result["price"] as? String,
              let read = ProductPage.shownPrice(text, currency: result["currency"] as? String)
        else { return nil }
        self.init(
            price: read.price,
            currency: read.currency?.uppercased(),
            origin: result["source"] as? String == "selector" ? .page : .shown
        )
    }
}

/// A page as a browser showed it once its scripts ran (`WebPagePriceReader` in the app):
/// the price it showed, and its words, for a summary when a plain request got none.
public struct RenderedPage: Sendable, Equatable {
    public var price: ShownPrice?
    public var text: String?

    public init(price: ShownPrice?, text: String?) {
        self.price = price
        self.text = text
    }
}
