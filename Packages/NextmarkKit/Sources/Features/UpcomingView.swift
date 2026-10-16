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

/// Shows and trips by date, soonest first (Docs/save_types.md): what's next is
/// always at the top. Past ones move to Done the morning after.
struct UpcomingView: View {
    let services: LibraryServices
    @State private var items: [ItemRecord] = []

    var body: some View {
        let now = Date()
        List {
            ForEach(Self.days(of: items, now: now), id: \.day) { group in
                Section {
                    ForEach(group.items) { item in
                        ItemLinkRow(item: item, services: services)
                    }
                } header: {
                    Text(Self.title(for: group.day, now: now))
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing Coming Up", systemImage: "calendar",
                    description: Text("Tickets, boarding passes and itineraries you save appear here by date, with reminders before they start.")
                )
            }
        }
        .navigationTitle("Upcoming")
        .task {
            for await snapshot in services.items.upcomingItems().ignoringErrors() {
                items = snapshot
            }
        }
    }

    struct Day {
        let day: Date
        let items: [ItemRecord]
    }

    static func days(of items: [ItemRecord], now: Date, calendar: Calendar = .current) -> [Day] {
        var order: [Date] = []
        var byDay: [Date: [ItemRecord]] = [:]
        for item in items {
            guard let next = item.nextDate(after: now) else { continue }
            let day = calendar.startOfDay(for: next.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item)
        }
        return order.map { Day(day: $0, items: byDay[$0] ?? []) }
    }

    /// "Today", "Tomorrow", "Saturday, Nov 21".
    static func title(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
