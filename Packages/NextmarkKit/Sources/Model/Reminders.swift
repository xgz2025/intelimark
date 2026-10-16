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

/// When to be reminded of a show or a departure (Docs/save_types.md).
public enum ReminderTime: Codable, Sendable, Hashable, Identifiable {
    /// A number of minutes before it starts or leaves.
    case before(minutes: Int)
    /// The day before, at an hour of the day ("the evening before").
    case dayBefore(hour: Int)

    public var id: String {
        switch self {
        case .before(let minutes): "before-\(minutes)"
        case .dayBefore(let hour): "daybefore-\(hour)"
        }
    }

    /// Earliest first, as Settings lists them.
    var leadMinutes: Int {
        switch self {
        case .before(let minutes): minutes
        case .dayBefore(let hour): 24 * 60 + (24 - hour) * 60
        }
    }
}

/// Which defaults a show or trip gets.
public enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    case show, flight, train

    /// Shows: the evening before at 18:00, and 2 hours before. Flights: 24 hours
    /// (check-in) and 3 hours before. Trains, buses and boats: 1 hour before.
    public var standard: [ReminderTime] {
        switch self {
        case .show: [.dayBefore(hour: 18), .before(minutes: 120)]
        case .flight: [.before(minutes: 24 * 60), .before(minutes: 180)]
        case .train: [.before(minutes: 60)]
        }
    }

    /// What Settings and an item offer to choose from.
    public var options: [ReminderTime] {
        let choices: [ReminderTime] = switch self {
        case .show: [.before(minutes: 7 * 24 * 60), .before(minutes: 24 * 60), .dayBefore(hour: 18), .before(minutes: 180), .before(minutes: 120), .before(minutes: 60), .before(minutes: 30)]
        case .flight: [.before(minutes: 2 * 24 * 60), .before(minutes: 24 * 60), .dayBefore(hour: 20), .before(minutes: 240), .before(minutes: 180), .before(minutes: 120)]
        case .train: [.before(minutes: 24 * 60), .dayBefore(hour: 20), .before(minutes: 120), .before(minutes: 60), .before(minutes: 30), .before(minutes: 15)]
        }
        return choices.sorted { $0.leadMinutes > $1.leadMinutes }
    }

    var defaultsKey: String { "reminders.\(rawValue)" }
}

/// The default reminders for each kind, kept in UserDefaults so Settings and the
/// planner read the same.
public enum ReminderDefaults {
    public static let enabledKey = "reminders.enabled"

    public static func times(for kind: ReminderKind, defaults: UserDefaults = .standard) -> [ReminderTime] {
        guard let data = defaults.data(forKey: kind.defaultsKey),
              let times = try? JSONDecoder().decode([ReminderTime].self, from: data)
        else { return kind.standard }
        return times
    }

    public static func set(_ times: [ReminderTime], for kind: ReminderKind, defaults: UserDefaults = .standard) {
        let sorted = times.sorted { $0.leadMinutes > $1.leadMinutes }
        defaults.set(try? JSONEncoder().encode(sorted), forKey: kind.defaultsKey)
    }

    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}
