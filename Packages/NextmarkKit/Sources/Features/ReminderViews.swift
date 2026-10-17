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

extension ReminderTime {
    /// "2 hours before", "The evening before, 18:00".
    var title: String {
        switch self {
        case .before(let minutes):
            if minutes % (24 * 60) == 0 {
                let days = minutes / (24 * 60)
                return days == 1 ? String(localized: "1 day before") : String(localized: "\(days) days before")
            }
            if minutes % 60 == 0 {
                let hours = minutes / 60
                return hours == 1 ? String(localized: "1 hour before") : String(localized: "\(hours) hours before")
            }
            return String(localized: "\(minutes) minutes before")
        case .dayBefore(let hour):
            let time = (Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date())
                .formatted(date: .omitted, time: .shortened)
            return hour >= 17 ? String(localized: "The evening before, \(time)") : String(localized: "The day before, \(time)")
        }
    }
}

extension ReminderKind {
    var title: LocalizedStringKey {
        switch self {
        case .show: "Shows"
        case .flight: "Flights"
        case .train: "Trains, Buses and Boats"
        }
    }

    var symbolName: String {
        switch self {
        case .show: "ticket"
        case .flight: "airplane"
        case .train: "tram.fill"
        }
    }

    /// "The evening before, 18:00 · 2 hours before", or "None".
    static func summary(_ times: [ReminderTime]) -> String {
        times.isEmpty ? String(localized: "None") : times.map(\.title).joined(separator: " · ")
    }
}

/// Checkmarks for the reminder times a kind offers.
struct ReminderTimesMenu<MenuLabel: View>: View {
    let kind: ReminderKind
    @Binding var selection: [ReminderTime]
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            ForEach(kind.options) { time in
                Toggle(time.title, isOn: Binding(
                    get: { selection.contains(time) },
                    set: { isOn in
                        if isOn {
                            selection.append(time)
                        } else {
                            selection.removeAll { $0 == time }
                        }
                    }
                ))
            }
        } label: {
            label()
        }
    }
}

/// Settings: the default reminders for shows, flights, and trains, buses and boats.
struct ReminderDefaultsSection: View {
    @AppStorage(ReminderDefaults.enabledKey) private var isEnabled = true
    @State private var times: [ReminderKind: [ReminderTime]] = Dictionary(
        uniqueKeysWithValues: ReminderKind.allCases.map { ($0, ReminderDefaults.times(for: $0)) }
    )
    let onChange: @Sendable () async -> Void

    var body: some View {
        Section {
            Toggle("Remind Me Before Shows and Trips", isOn: $isEnabled)
            if isEnabled {
                ForEach(ReminderKind.allCases, id: \.self) { kind in
                    ReminderTimesMenu(kind: kind, selection: binding(for: kind)) {
                        LabeledContent {
                            Text(ReminderKind.summary(times[kind] ?? []))
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label(kind.title, systemImage: kind.symbolName)
                        }
                    }
                }
            }
        } header: {
            Text("Shows and Trips")
        } footer: {
            Text("Free for every ticket and trip you save. You can change them on each one. They keep their time, even in quiet hours.")
        }
        .onChange(of: isEnabled) { reschedule() }
    }

    private func binding(for kind: ReminderKind) -> Binding<[ReminderTime]> {
        Binding(
            get: { times[kind] ?? [] },
            set: { newValue in
                times[kind] = newValue
                ReminderDefaults.set(newValue, for: kind)
                reschedule()
            }
        )
    }

    private func reschedule() {
        let onChange = onChange
        Task { await onChange() }
    }
}

/// An item's own reminders: its kind's defaults until changed here.
struct ItemRemindersSection: View {
    let item: ItemRecord
    let services: LibraryServices
    @AppStorage(ReminderDefaults.enabledKey) private var isEnabled = true

    private var kind: ReminderKind {
        guard item.saveType == .travel else { return .show }
        switch item.typedFields?.trip?.mode {
        case .train, .bus, .boat: return .train
        default: return .flight
        }
    }

    private var current: [ReminderTime] {
        item.reminders ?? ReminderDefaults.times(for: kind)
    }

    var body: some View {
        Section {
            if isEnabled {
                ReminderTimesMenu(kind: kind, selection: Binding(get: { current }, set: { save($0) })) {
                    LabeledContent {
                        Text(ReminderKind.summary(current))
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Remind Me", systemImage: "bell")
                    }
                }
                if item.reminders != nil {
                    Button("Use My Usual Reminders") { save(nil) }
                }
            } else {
                Text("Reminders for shows and trips are off in Settings.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Reminders")
        }
    }

    private func save(_ reminders: [ReminderTime]?) {
        let (items, id, refresh) = (services.items, item.id, services.refresh)
        let sorted = reminders.map { $0.sorted { lhs, rhs in kind.options.firstIndex(of: lhs) ?? 0 < kind.options.firstIndex(of: rhs) ?? 0 } }
        performEdit {
            try await items.setReminders(sorted, forItem: id)
            await refresh()
        }
    }
}
