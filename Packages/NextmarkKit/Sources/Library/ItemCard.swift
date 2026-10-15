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

/// How an item reads at a glance, by what it is: a receipt by its merchant and total,
/// a photo by what it shows and where, a document by its title and author, a web page
/// like a search result. Built from facts only, so it's the same on every device.
public struct ItemCard: Sendable, Equatable {
    public enum Style: Sendable, Equatable {
        case web, article, document, receipt, photo, product, event, recipe, place, note
    }

    public var style: Style
    public var title: String
    /// Above the title, small: where it's from ("example.com › recipes › ramen").
    public var source: String?
    /// Under the title: who and when ("Jane Doe · The Atlantic · Oct 3, 2026").
    public var byline: String?
    /// The figure that matters at a glance: a receipt's total, a product's price.
    public var figure: String?
    /// What it is, in a line or two.
    public var snippet: String?
}

extension ItemRecord {
    public var card: ItemCard {
        let fields = typedFields
        let kind = semanticKind ?? structuredKind
        var card = ItemCard(style: .note, title: displayTitle)

        if kind == .receipt || fields?.receipt != nil {
            card.style = .receipt
            if userTitle == nil, let merchant = fields?.receipt?.merchant { card.title = merchant }
            card.figure = fields?.receipt?.total.map { Self.money($0, currency: fields?.receipt?.currency) }
            // The receipt's own date, else when the photo was taken; never the day it was saved.
            let date = fields?.receipt?.purchasedAt ?? fields?.photo?.takenAt
            card.byline = Self.join([fields?.photo?.placeName, date.map(Self.day)])
            return card
        }

        switch self.kind {
        case .image:
            card.style = .photo
            card.byline = Self.join([fields?.photo?.placeName, fields?.photo?.takenAt.map(Self.day)])
            card.snippet = Self.distinct(imageDescription ?? summary, from: card.title)
        case .pdf, .file:
            card.style = .document
            let article = fields?.article
            if userTitle == nil, let headline = article?.headline { card.title = headline }
            card.byline = Self.join([article?.author, article?.publisher, article?.publishedAt.map(Self.day)])
            card.snippet = Self.distinct(summary, from: card.title)
        case .link:
            card.style = .web
            card.source = Self.breadcrumb(canonicalURL, siteName: siteName)
            card.snippet = Self.distinct(summary, from: card.title)
            if let product = fields?.product {
                card.style = .product
                card.figure = product.price.map { Self.money($0, currency: product.currency) }
                card.byline = product.brand
            } else if let event = fields?.event {
                card.style = .event
                card.byline = Self.join([event.startDate.map(Self.day), event.venue])
            } else if let recipe = fields?.recipe {
                card.style = .recipe
                card.byline = Self.join([
                    recipe.totalMinutes.map { String(localized: "\($0) min") },
                    recipe.servings.map { String(localized: "Serves \($0)") },
                ])
            } else if let place = fields?.place {
                card.style = .place
                card.byline = place.address
            } else if let article = fields?.article, article.author != nil || article.publishedAt != nil {
                card.style = .article
                card.byline = Self.join([article.author, article.publishedAt.map(Self.day)])
            }
        case .text, .note, .email, .aiSession:
            card.snippet = Self.distinct(summary, from: card.title)
        }
        return card
    }

    /// "example.com › recipes › ramen-guide": the host without "www.", and the first
    /// path segments, as a search result shows them.
    static func breadcrumb(_ address: String?, siteName: String?) -> String? {
        guard let address, let url = URL(string: address), var host = url.host() else { return siteName }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let segments = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .prefix(2)
            .map { segment in
                let readable = segment.removingPercentEncoding ?? segment
                return readable.count > 24 ? String(readable.prefix(23)) + "…" : readable
            }
        return ([host] + segments).joined(separator: " › ")
    }

    static func money(_ amount: Double, currency: String?) -> String {
        guard let currency else { return amount.formatted(.number.precision(.fractionLength(2))) }
        return amount.formatted(.currency(code: currency))
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func join(_ parts: [String?]) -> String? {
        let present = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }

    /// `text`, unless it only repeats the title.
    static func distinct(_ text: String?, from title: String) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.caseInsensitiveCompare(title) == .orderedSame || title.hasPrefix(text) ? nil : text
    }
}
