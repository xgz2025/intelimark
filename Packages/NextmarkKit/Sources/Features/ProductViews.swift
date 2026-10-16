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
import PhotosUI
import UniformTypeIdentifiers
import Model
import Library
import Extraction

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
            String(localized: "The shop's page didn't show Laterwise a price (it may need a sign-in). The price you saved stays: update it from the page in Safari, or from a screenshot.")
        }
    }
}

/// A product's price: now, since it was saved, its history, and Check Price.
struct ProductPriceSection: View {
    let item: ItemRecord
    let services: LibraryServices
    @State private var isChecking = false
    @State private var result: String?
    @State private var targetText = ""
    @FocusState private var isEditingTarget: Bool
    @State private var isReadingPicture = false
    @State private var pictureMentions: [PriceText.Mention] = []
    @State private var showsMentions = false
    #if os(iOS)
    @State private var picture: PhotosPickerItem?
    #else
    @State private var showsImporter = false
    #endif

    private var product: ProductFields? { item.typedFields?.product }
    private var link: URL? { item.canonicalURL.flatMap { URL(string: $0) } }

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 4) {
                    TextField("None", text: $targetText)
                        .multilineTextAlignment(.trailing)
                        .focused($isEditingTarget)
                        .onSubmit { saveTarget() }
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    if let currency = product?.currency {
                        Text(currency).foregroundStyle(.secondary)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Price")
                    Text("Tell me when it's at or under this")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: isEditingTarget) { _, editing in
                if !editing { saveTarget() }
            }
            if let status = targetStatus {
                Label(status.text, systemImage: status.reached ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(status.reached ? .green : .secondary)
                    .font(.callout)
            }
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
            if let link {
                Link(destination: link) {
                    Label("Update from the Page in Safari", systemImage: "safari")
                }
                .help(Text("Open the page, then tap Laterwise in Safari's toolbar or Share menu"))
            }
            readFromPicture
        } header: {
            Text("Price")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let checked = product?.checkedAt {
                    Text("Checked \(checked.formatted(.relative(presentation: .named))).")
                }
                Text("Check Price opens the shop's page on this device, as a browser shows it, without your sign-in. For a price only you see (a member price, a shop's app), open the page in Safari and tap Laterwise, or read it from a screenshot.")
            }
        }
        .confirmationDialog("Which Is the Price?", isPresented: $showsMentions, titleVisibility: .visible) {
            ForEach(pictureMentions, id: \.self) { mention in
                Button {
                    record(mention)
                } label: {
                    Text(verbatim: "\(ItemRecord.money(mention.price, currency: mention.currency ?? product?.currency)) · \(mention.line)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Prices read from the picture. Pick the one you'd pay now.")
        }
        .onAppear { targetText = Self.text(for: item.targetPrice) }
        .onChange(of: item.targetPrice) { _, price in
            if !isEditingTarget { targetText = Self.text(for: price) }
        }
    }

    /// A screenshot of the shop's page or app: its prices read on this device, for the
    /// person to pick the real one (an app's own page, a price behind a sign-in).
    @ViewBuilder
    private var readFromPicture: some View {
        let isReading = isReadingPicture
        #if os(iOS)
        PhotosPicker(selection: $picture, matching: .images, photoLibrary: .shared()) { Self.pictureLabel(isReading: isReading) }
            .disabled(isReadingPicture)
            .onChange(of: picture) { _, selection in
                guard let selection else { return }
                picture = nil
                isReadingPicture = true
                Task {
                    let data = try? await selection.loadTransferable(type: Data.self)
                    await readPrices(in: data)
                }
            }
        #else
        Button { showsImporter = true } label: { Self.pictureLabel(isReading: isReading) }
            .disabled(isReadingPicture)
            .help(Text("Choose a screenshot of the product's page; Laterwise reads its prices on this Mac"))
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                isReadingPicture = true
                Task {
                    let accessing = url.startAccessingSecurityScopedResource()
                    let data = try? Data(contentsOf: url)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                    await readPrices(in: data)
                }
            }
        #endif
    }

    nonisolated private static func pictureLabel(isReading: Bool) -> some View {
        HStack {
            Label("Read Price from Screenshot…", systemImage: "text.viewfinder")
            Spacer()
            if isReading { ProgressView().controlSize(.small) }
        }
    }

    private func readPrices(in data: Data?) async {
        defer { isReadingPicture = false }
        guard let data, let text = try? await VisionImageAnalyzer().analyze(imageData: data).text else {
            result = String(localized: "Laterwise couldn't read any text in that picture.")
            return
        }
        let mentions = PriceText.all(in: text)
        if mentions.isEmpty {
            result = String(localized: "No price found in that picture. Try a screenshot that shows the price.")
        } else {
            result = nil
            pictureMentions = mentions
            showsMentions = true
        }
    }

    private func record(_ mention: PriceText.Mention) {
        let (items, id) = (services.items, item.id)
        let currency = mention.currency ?? product?.currency
        result = String(localized: "Now \(ItemRecord.money(mention.price, currency: currency)).")
        performEdit { _ = try await items.recordPrice(mention.price, currency: currency, origin: .user, forItem: id) }
    }

    /// How the price stands against the target.
    private var targetStatus: (text: String, reached: Bool)? {
        guard let target = item.targetPrice, let price = product?.price else { return nil }
        if price <= target { return (String(localized: "At or under your target."), true) }
        let gap = ItemRecord.money(price - target, currency: product?.currency)
        return (String(localized: "\(gap) above your target."), false)
    }

    static func text(for price: Double?) -> String {
        price.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
    }

    /// "299", "299.5", "1 299,90": the number typed, read in the person's locale.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed.replacingOccurrences(of: " ", with: "")) {
            return number.doubleValue
        }
        return Double(trimmed.filter { $0.isNumber || $0 == "." })
    }

    private func saveTarget() {
        let price = Self.parse(targetText)
        guard price != item.targetPrice else { return }
        let (items, id) = (services.items, item.id)
        performEdit { try await items.setTargetPrice(price, forItem: id) }
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

/// A group's products side by side, cheapest first: what comparing is for. Each has
/// its own Check Price; Pro checks the whole group from the group's title line.
struct ComparisonSection: View {
    let members: [ItemRecord]
    let services: LibraryServices
    /// Takes a product out of the group (it stays in the library).
    let removeFromGroup: (String) -> Void
    @State private var checking: Set<String> = []
    @State private var results: [String: String] = [:]

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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        NavigationLink(value: ItemLink(id: item.id)) {
                            ComparisonRow(item: item, isCheapest: cheapest != nil && item.typedFields?.product?.price == cheapest
                                            && item.typedFields?.product?.currency == mainCurrency)
                                .id(item.rowVersion)
                        }
                        checkButton(for: item)
                    }
                    if let result = results[item.id] {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("Check Price", systemImage: "arrow.clockwise") { check(item) }
                        .disabled(item.canonicalURL == nil || checking.contains(item.id))
                    Button("Remove from Group", systemImage: "minus.circle") { removeFromGroup(item.id) }
                }
                .swipeActions {
                    Button("Remove", systemImage: "minus.circle", role: .destructive) { removeFromGroup(item.id) }
                }
            }
        } header: {
            Text("Compare")
        } footer: {
            Text("Cheapest first. Prices are as each shop's page last showed them.")
        }
    }

    @ViewBuilder
    private func checkButton(for item: ItemRecord) -> some View {
        if checking.contains(item.id) {
            ProgressView().controlSize(.small)
        } else {
            Button {
                check(item)
            } label: {
                Label("Check Price", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(item.canonicalURL == nil)
            .help(Text("Read this shop's page again for its current price"))
        }
    }

    private func check(_ item: ItemRecord) {
        let (checkPrices, id, currency) = (services.checkPrices, item.id, item.typedFields?.product?.currency)
        checking.insert(id)
        results[id] = nil
        Task {
            let outcome = await checkPrices([id])[id] ?? .unavailable
            results[id] = outcome.message(currency: currency)
            checking.remove(id)
        }
    }
}

/// Checks every product in a group at once, from the group's title line: Pro. Free
/// checks them one by one in the Compare list.
struct GroupPriceCheckButton: View {
    let itemIDs: [String]
    let services: LibraryServices
    let isPro: Bool
    @Binding var summary: String?
    @State private var isChecking = false
    @State private var showsPaywall = false

    var body: some View {
        Group {
            if isChecking {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    if isPro { check() } else { showsPaywall = true }
                } label: {
                    Label(isPro ? LocalizedStringKey("Check Prices") : "Check All with Pro", systemImage: isPro ? "arrow.clockwise" : "lock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Text("Read each shop's page again for its current price"))
            }
        }
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView(reason: "Pro checks a whole group's prices at once, and every day on its own.")
        }
    }

    private func check() {
        isChecking = true
        summary = nil
        let (checkPrices, ids) = (services.checkPrices, itemIDs)
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
                if card.isUnderTarget {
                    Text("Under target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if isCheapest {
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
