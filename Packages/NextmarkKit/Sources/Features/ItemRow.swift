import SwiftUI
import Library
import DesignSystem

struct ItemRow: View {
    let item: ItemRecord
    @Environment(\.itemsDirectory) private var itemsDirectory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumbnail = item.thumbnailURL(in: itemsDirectory) {
                ItemThumbnail(url: thumbnail, symbolName: item.kind.symbolName)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: item.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(2)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let intent = item.intent ?? item.suggestedIntent {
                Image(systemName: intent.symbolName)
                    .foregroundStyle(intent.tint)
                    .accessibilityLabel(Text(intent.title))
            }
        }
        .padding(.vertical, 2)
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
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
