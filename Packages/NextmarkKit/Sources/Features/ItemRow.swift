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
import Model
import Library
import DesignSystem

extension ItemRecord {
    /// Changes whenever what a row shows changes: its identity in lists, so a row is
    /// redrawn when the page is read, a price found or the title written.
    var rowVersion: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(updatedAt)
        hasher.combine(typedFields)
        hasher.combine(siteName)
        hasher.combine(userTitle)
        hasher.combine(sourceTitle)
        hasher.combine(aiTitle)
        hasher.combine(summary)
        hasher.combine(heroImageURL)
        hasher.combine(intent)
        hasher.combine(suggestedIntent)
        hasher.combine(targetPrice)
        return hasher.finalize()
    }
}

extension ItemRecord {
    /// A list's identity for the row: the item and its version. The Mac's lists keep a
    /// row's content and height until its identity changes, so a row whose page was
    /// just read (a price, a summary) is replaced rather than left as it was.
    var listID: String { "\(id)#\(rowVersion)" }
}

struct ItemRow: View {
    let item: ItemRecord
    @Environment(\.itemsDirectory) private var itemsDirectory

    var body: some View {
        let card = item.card
        HStack(alignment: .top, spacing: 12) {
            leading(card)
            VStack(alignment: .leading, spacing: 3) {
                if let source = card.source {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(card.style == .web ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let figure = card.figure {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(figure)
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                            if card.isUnderTarget {
                                Label("Under target", systemImage: "checkmark.circle.fill")
                                    .labelStyle(BylineLabelStyle())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else if let change = card.change {
                                Text(change)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(card.isDrop ? .green : .red)
                            }
                        }
                    }
                }
                if let byline = card.byline {
                    Label {
                        Text(byline)
                    } icon: {
                        if item.typedFields?.photo?.placeName != nil, card.style == .photo || card.style == .receipt {
                            Image(systemName: "mappin")
                        }
                    }
                    .labelStyle(BylineLabelStyle())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                if let snippet = card.snippet {
                    Text(snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("Saved \(Self.savedTime(item.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let intent = item.intent ?? item.suggestedIntent {
                Image(systemName: intent.symbolName)
                    .font(.footnote)
                    .foregroundStyle(intent.tint)
                    .padding(.top, 2)
                    .accessibilityLabel(Text(intent.title))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "14:03" today, "Yesterday 14:03", "Oct 3" earlier.
    static func savedTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "yesterday at \(date.formatted(date: .omitted, time: .shortened))")
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    @ViewBuilder
    private func leading(_ card: ItemCard) -> some View {
        if card.style == .product, let image = item.typedFields?.product?.imageURL.flatMap(URL.init(string:)) ?? item.heroImageURL.flatMap(URL.init(string:)) {
            ItemThumbnail(url: image, symbolName: "bag")
                .frame(width: 48, height: 48)
        } else if let thumbnail = item.thumbnailURL(in: itemsDirectory) {
            ItemThumbnail(url: thumbnail, symbolName: item.kind.symbolName)
                .frame(width: 48, height: 48)
                // The Extract stage writes the file later; a new `updatedAt` loads it again.
                .id(item.updatedAt)
        } else {
            CardBadge(card: card, item: item)
        }
    }
}

/// The site's initial for a web page, the kind's symbol for anything else, in a
/// softly tinted square.
struct CardBadge: View {
    let card: ItemCard
    let item: ItemRecord

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(card.style.tint.opacity(0.15))
            if card.style == .web, let initial = card.source?.first {
                Text(String(initial).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(card.style.tint)
            } else {
                Image(systemName: card.style == .travel ? item.travelSymbol : card.style.symbolName(for: item.kind))
                    .font(.headline)
                    .foregroundStyle(card.style.tint)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }
}

/// An icon only when there is one, close to the text.
private struct BylineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

extension ItemCard.Style {
    var tint: Color {
        switch self {
        case .web, .article: .blue
        case .document: .indigo
        case .receipt: .green
        case .photo: .orange
        case .product: .mint
        case .event: .red
        case .recipe: .pink
        case .place: .teal
        case .note: .gray
        case .travel: .purple
        }
    }

    func symbolName(for kind: ItemKind) -> String {
        switch self {
        case .web: "globe"
        case .article: "doc.text"
        case .document: "doc.richtext"
        case .receipt: "receipt"
        case .photo: "photo"
        case .product: "bag"
        case .event: "calendar"
        case .recipe: "fork.knife"
        case .place: "mappin.and.ellipse"
        case .note: kind.symbolName
        case .travel: "airplane"
        }
    }
}

extension ItemRecord {
    /// A plane, train, bus or boat, by how the trip goes.
    var travelSymbol: String {
        switch typedFields?.trip?.mode {
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .boat: "ferry.fill"
        default: "airplane"
        }
    }
}

/// A rounded preview; the kind's symbol until the thumbnail exists.
struct ItemThumbnail: View {
    let url: URL?
    let symbolName: String

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
