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
import Library

struct InboxView: View {
    let services: LibraryServices
    @State private var items: [ItemRecord] = []
    @State private var errorMessage: String?

    private var captures: CaptureStatus { CaptureStatus.shared }

    var body: some View {
        List {
            if captures.stuckCount > 0 {
                Section {
                    Label(
                        "^[\(captures.stuckCount) save](inflect: true) couldn't be added to your library yet.",
                        systemImage: "exclamationmark.triangle"
                    )
                    if let reason = captures.reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Try Again") {
                        let refresh = services.refresh
                        Task { await refresh() }
                    }
                } footer: {
                    Text("They're kept safe until they can be added. Freeing up storage on this device usually helps.")
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            ForEach(DaySection.sections(of: items, date: \.createdAt)) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        ItemLinkRow(item: item, services: services)
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty, captures.stuckCount == 0, errorMessage == nil {
                ContentUnavailableView(
                    "Nothing saved yet", systemImage: "tray",
                    description: Text("Tap Share in any app and choose Nextmark.")
                )
            }
        }
        .navigationTitle("Inbox")
        .task {
            do {
                for try await snapshot in services.items.inboxItems() {
                    items = snapshot
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Items by when they were saved: Today, Yesterday, This Week, Earlier.
struct DaySection<Element: Identifiable>: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let items: [Element]

    static func sections(
        of items: [Element], date: (Element) -> Date, now: Date = Date(), calendar: Calendar = .current
    ) -> [DaySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        var buckets: [[Element]] = [[], [], [], []]
        for item in items {
            let day = date(item)
            let index = day >= today ? 0 : day >= yesterday ? 1 : day >= weekAgo ? 2 : 3
            buckets[index].append(item)
        }
        let titles: [LocalizedStringKey] = ["Today", "Yesterday", "This Week", "Earlier"]
        return buckets.indices
            .filter { !buckets[$0].isEmpty }
            .map { DaySection(id: $0, title: titles[$0], items: buckets[$0]) }
    }
}
