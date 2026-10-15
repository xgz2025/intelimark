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

/// The last time items were marked done, trashed or brought back, so it can be
/// undone from a banner at the bottom of the window (or ⌘Z) for a few seconds.
@MainActor
@Observable
final class RecentChange {
    static let shared = RecentChange()

    struct Change: Identifiable {
        let id = UUID()
        let status: ItemStatus
        /// What each item was before, to put it back.
        let previous: [String: ItemStatus]
        let title: String?
    }

    private(set) var change: Change?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    static let visibleFor: Duration = .seconds(6)

    func record(_ change: Change) {
        self.change = change
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.clear(change.id)
        }
    }

    func clear(_ id: UUID? = nil) {
        guard id == nil || change?.id == id else { return }
        change = nil
    }

    /// Puts every item back where it was.
    func undo(using items: ItemRepository) {
        guard let change else { return }
        clear()
        let byStatus = Dictionary(grouping: change.previous.keys) { change.previous[$0] ?? .active }
        performEdit {
            for (status, ids) in byStatus {
                try await items.setStatus(status, forItems: ids)
            }
        }
    }
}

/// Marks items done, trashes them or brings them back, and offers Undo.
@MainActor
func changeStatus(_ status: ItemStatus, of items: [ItemRecord], using repository: ItemRepository) {
    let changing = items.filter { $0.status != status }
    guard !changing.isEmpty else { return }
    let previous = Dictionary(changing.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
    let ids = changing.map(\.id)
    performEdit {
        try await repository.setStatus(status, forItems: ids)
        RecentChange.shared.record(.init(
            status: status, previous: previous, title: changing.count == 1 ? changing[0].displayTitle : nil
        ))
    }
}

extension View {
    /// The Undo banner for `RecentChange`. Attach once, at the root.
    func recentChangeBanner(items: ItemRepository) -> some View {
        overlay(alignment: .bottom) {
            RecentChangeBanner(items: items)
        }
    }
}

private struct RecentChangeBanner: View {
    let items: ItemRepository
    private var recent: RecentChange { RecentChange.shared }

    var body: some View {
        if let change = recent.change {
            HStack(spacing: 12) {
                Image(systemName: Self.symbol(for: change.status))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Self.message(for: change)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Undo") { recent.undo(using: items) }
                    .keyboardShortcut("z", modifiers: .command)
                    .bold()
                Button {
                    recent.clear()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Close"))
                .help(Text("Close"))
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 520)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(change.id)
            .accessibilityElement(children: .contain)
        }
    }

    static func symbol(for status: ItemStatus) -> String {
        switch status {
        case .done: "checkmark.circle"
        case .trashed: "trash"
        default: "tray"
        }
    }

    static func message(for change: RecentChange.Change) -> Text {
        let count = change.previous.count
        switch (change.status, change.title) {
        case (.done, let title?): return Text("Marked “\(title)” as done. Find it in Done.")
        case (.done, nil): return Text("Marked \(count) items as done. Find them in Done.")
        case (.trashed, let title?): return Text("Moved “\(title)” to the Trash.")
        case (.trashed, nil): return Text("Moved \(count) items to the Trash.")
        case (_, let title?): return Text("Moved “\(title)” back to the Inbox.")
        case (_, nil): return Text("Moved \(count) items back to the Inbox.")
        }
    }
}
