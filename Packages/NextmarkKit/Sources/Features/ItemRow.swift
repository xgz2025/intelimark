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
                        Text(figure)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
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

    @ViewBuilder
    private func leading(_ card: ItemCard) -> some View {
        if let thumbnail = item.thumbnailURL(in: itemsDirectory) {
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
                Image(systemName: card.style.symbolName(for: item.kind))
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
