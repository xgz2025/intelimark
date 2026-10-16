//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import SwiftUI
import Charts
import Model
import Library

/// What a Check Price found, in a sentence.
extension PriceCheckOutcome {
    func message(currency: String?) -> String {
        switch self {
        case .dropped(let from, let to, _):
            String(localized: "Down to \(ItemRecord.money(to, currency: currency)) from \(ItemRecord.money(from, currency: currency)).")
        case .rose(let from, let to, _):
            String(localized: "Up to \(ItemRecord.money(to, currency: currency)) from \(ItemRecord.money(from, currency: currency)).")
        case .unchanged(let price):
            String(localized: "Still \(ItemRecord.money(price, currency: currency)).")
        case .found(let price):
            String(localized: "Now \(ItemRecord.money(price, currency: currency)).")
        case .unavailable:
            String(localized: "The shop's page didn't show a price to Laterwise (it may need a browser or a sign-in). The price you saved stays.")
        }
    }
}

/// A product's price: now, since it was saved, its history, and Check Price.
struct ProductPriceSection: View {
    let item: ItemRecord
    let services: LibraryServices
    @State private var isChecking = false
    @State private var result: String?

    private var product: ProductFields? { item.typedFields?.product }

    var body: some View {
        Section {
            if let history = product?.priceHistory, history.count >= 2 {
                Chart(history, id: \.at) { point in
                    LineMark(x: .value("Date", point.at), y: .value("Price", point.price))
                        .interpolationMethod(.stepEnd)
                    PointMark(x: .value("Date", point.at), y: .value("Price", point.price))
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                .accessibilityLabel(Text("Price history"))
            }
            Button {
                check()
            } label: {
                HStack {
                    Label("Check Price", systemImage: "arrow.clockwise")
                    Spacer()
                    if isChecking { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isChecking || item.canonicalURL == nil)
            .help(Text("Read the shop's page again for its current price"))
            if let result {
                Text(result)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Price")
        } footer: {
            if let checked = product?.checkedAt {
                Text("Checked \(checked.formatted(.relative(presentation: .named))).")
            }
        }
    }

    private func check() {
        isChecking = true
        result = nil
        let (checkPrices, id, currency) = (services.checkPrices, item.id, product?.currency)
        Task {
            let outcome = await checkPrices([id])[id] ?? .unavailable
            result = outcome.message(currency: currency)
            isChecking = false
        }
    }
}

/// A group's products side by side, cheapest first: what comparing is for.
struct ComparisonSection: View {
    let members: [ItemRecord]
    let services: LibraryServices
    @State private var isChecking = false
    @State private var summary: String?

    /// Cheapest first; those without a price (or in another currency) after.
    private var ranked: [ItemRecord] {
        let currency = mainCurrency
        return members.sorted { lhs, rhs in
            let left = lhs.typedFields?.product, right = rhs.typedFields?.product
            let leftComparable = left?.price != nil && left?.currency == currency
            let rightComparable = right?.price != nil && right?.currency == currency
            if leftComparable != rightComparable { return leftComparable }
            return (left?.price ?? .infinity) < (right?.price ?? .infinity)
        }
    }

    /// The currency most of the products are priced in.
    private var mainCurrency: String? {
        let currencies = members.compactMap { $0.typedFields?.product?.currency }
        return Dictionary(grouping: currencies, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    var body: some View {
        let sorted = ranked
        let cheapest = sorted.first?.typedFields?.product?.price
        Section {
            ForEach(sorted) { item in
                NavigationLink(value: ItemLink(id: item.id)) {
                    ComparisonRow(item: item, isCheapest: cheapest != nil && item.typedFields?.product?.price == cheapest
                                    && item.typedFields?.product?.currency == mainCurrency)
                }
            }
            Button {
                check()
            } label: {
                HStack {
                    Label("Check Prices", systemImage: "arrow.clockwise")
                    Spacer()
                    if isChecking { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isChecking)
            .help(Text("Read each shop's page again for its current price"))
            if let summary {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Compare")
        } footer: {
            Text("Cheapest first. Prices are as each shop's page last showed them.")
        }
    }

    private func check() {
        isChecking = true
        summary = nil
        let (checkPrices, ids) = (services.checkPrices, members.map(\.id))
        Task {
            let outcomes = await checkPrices(ids)
            let dropped = outcomes.values.filter { if case .dropped = $0 { true } else { false } }.count
            let unreadable = outcomes.values.filter { $0 == .unavailable }.count
            var parts: [String] = []
            parts.append(dropped == 0 ? String(localized: "No price drops.") : String(localized: "\(dropped) got cheaper."))
            if unreadable > 0 { parts.append(String(localized: "\(unreadable) shops didn't show a price; their saved prices stay.")) }
            summary = parts.joined(separator: " ")
            isChecking = false
        }
    }
}

private struct ComparisonRow: View {
    let item: ItemRecord
    let isCheapest: Bool

    var body: some View {
        let card = item.card
        HStack(spacing: 12) {
            if let image = item.typedFields?.product?.imageURL.flatMap(URL.init(string:)) {
                ItemThumbnail(url: image, symbolName: "bag")
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).lineLimit(2)
                if let byline = card.byline {
                    Text(byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(card.figure ?? "—")
                    .font(.body.weight(.semibold).monospacedDigit())
                if isCheapest {
                    Text("Lowest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if let change = card.change {
                    Text(change)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(card.isDrop ? .green : .red)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
