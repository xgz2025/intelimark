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
        case web, article, document, receipt, photo, product, event, recipe, place, note, travel
    }

    public var style: Style
    public var title: String
    /// Above the title, small: where it's from ("example.com › recipes › ramen").
    public var source: String?
    /// Under the title: who and when ("Jane Doe · The Atlantic · Oct 3, 2026").
    public var byline: String?
    /// The figure that matters at a glance: a receipt's total, a product's price.
    public var figure: String?
    /// A product's price change since it was saved ("↓ $50.00").
    public var change: String?
    /// True when `change` is a drop.
    public var isDrop = false
    /// A product at or under the price the person wants it at.
    public var isUnderTarget = false
    /// What it is, in a line or two.
    public var snippet: String?
}

extension ItemRecord {
    public var card: ItemCard {
        let fields = typedFields
        var card = ItemCard(style: .note, title: displayTitle)

        switch saveType {
        case .travel:
            card.style = .travel
            let leg = fields?.trip?.currentLeg()
            if userTitle == nil, let leg, let from = leg.fromLabel ?? leg.fromCode, let to = leg.toLabel ?? leg.toCode {
                card.title = "\(from) → \(to)"
            }
            let departure = leg?.departure.map { ItemDate(date: $0, hasTime: leg?.departureHasTime ?? true, role: .departure, source: .structured) }
                ?? departures.first
            card.byline = Self.join([leg.flatMap(Self.legNumber), departure.map(Self.when)])
            card.snippet = Self.join([
                leg?.terminal.map { String(localized: "Terminal \($0)") },
                leg?.platform.map { String(localized: "Platform \($0)") },
                leg?.seat.map { String(localized: "Seat \($0)") },
            ])
            return card
        case .show:
            card.style = .event
            if userTitle == nil, let name = fields?.ticket?.name ?? fields?.event?.name { card.title = name }
            let venue = fields?.ticket?.venue ?? fields?.event?.venue ?? places.first?.name
            card.byline = Self.join([showStart.map(Self.when), venue])
            card.snippet = fields?.ticket?.seat.map { String(localized: "Seat \($0)") }
            return card
        case .receipt:
            card.style = .receipt
            if userTitle == nil, let merchant = fields?.receipt?.merchant { card.title = merchant }
            card.figure = fields?.receipt?.total.map { Self.money($0, currency: fields?.receipt?.currency) }
            // The receipt's own date, else when the photo was taken; never the day it was saved.
            let date = fields?.receipt?.purchasedAt ?? fields?.photo?.takenAt
            card.byline = Self.join([fields?.photo?.placeName, date.map(Self.day)])
            return card
        case .product:
            card.style = .product
            let product = fields?.product
            if userTitle == nil, let name = product?.name { card.title = name }
            card.source = Self.breadcrumb(canonicalURL, siteName: siteName)
            card.figure = product?.price.map { Self.money($0, currency: product?.currency) }
            if let change = product?.changeSinceSaved {
                card.change = (change < 0 ? "↓ " : "↑ ") + Self.money(abs(change), currency: product?.currency)
                card.isDrop = change < 0
            }
            if let target = targetPrice, let price = product?.price, price <= target { card.isUnderTarget = true }
            card.byline = Self.join([product?.store ?? siteName, product?.brand])
            card.snippet = Self.distinct(product?.description ?? summary, from: card.title)
            return card
        default:
            break
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
            if let recipe = fields?.recipe {
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

    /// "MU 523" or "China Eastern MU 523".
    static func legNumber(_ leg: TripLeg) -> String? {
        switch (leg.carrier, leg.number) {
        case let (carrier?, number?) where !number.hasPrefix(carrier): "\(carrier) \(number)"
        case let (_, number?): number
        case let (carrier?, nil): carrier
        default: nil
        }
    }

    /// "Tue, Oct 20, 14:05", or the day alone when no time is known.
    static func when(_ date: ItemDate) -> String {
        date.hasTime
            ? date.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            : date.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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

    public static func money(_ amount: Double, currency: String?) -> String {
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
