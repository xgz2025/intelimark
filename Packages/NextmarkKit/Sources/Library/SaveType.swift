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
import Model

/// What a save is, whatever its format (Docs/save_types.md): it decides the card,
/// the Details, and whether it gets reminders.
public enum SaveType: String, Sendable, Hashable, CaseIterable {
    case article, receipt, show, travel, product, link, other
}

extension ItemRecord {
    public var saveType: SaveType {
        let fields = typedFields
        let kind = semanticKind ?? structuredKind
        if fields?.trip != nil || kind == .travel { return .travel }
        if fields?.ticket != nil || fields?.event != nil || kind == .ticket || kind == .event { return .show }
        if fields?.receipt != nil || kind == .receipt { return .receipt }
        if fields?.product != nil || kind == .product { return .product }
        if fields?.article != nil || kind == .article || kind == .document || self.kind == .pdf { return .article }
        if self.kind == .link { return .link }
        return .other
    }

    /// Every date the item states or was found to state, structured first.
    var allDates: [ItemDate] {
        FactMerge.dates(structured: typedFields?.structuredDates ?? [], inferred: dates)
    }

    /// When a show starts.
    public var showStart: ItemDate? {
        allDates.filter { $0.role == .eventStart }.min { $0.date < $1.date }
    }

    /// When each leg of a trip leaves, earliest first.
    public var departures: [ItemDate] {
        allDates.filter { $0.role == .departure }.sorted { $0.date < $1.date }
    }

    /// What Upcoming sorts by: a show's start, or a trip's next departure.
    public func nextDate(after now: Date) -> ItemDate? {
        switch saveType {
        case .show: showStart.flatMap { Self.stillAhead($0, now: now) ? $0 : nil }
        case .travel: departures.first { Self.stillAhead($0, now: now) }
        default: nil
        }
    }

    /// When a show or trip is over: its end, else its last start or departure.
    public var endsAt: Date? {
        switch saveType {
        case .show:
            let end = allDates.filter { $0.role == .eventEnd }.map(\.date).max()
            return end ?? showStart.map(Self.endOfStart)
        case .travel:
            return typedFields?.trip?.end ?? departures.last.map(Self.endOfStart)
        default:
            return nil
        }
    }

    /// A date without a time lasts all day; one with a time, a few hours.
    static func endOfStart(_ date: ItemDate) -> Date {
        date.hasTime ? date.date.addingTimeInterval(3 * 3600) : Calendar.current.startOfDay(for: date.date).addingTimeInterval(86_400)
    }

    static func stillAhead(_ date: ItemDate, now: Date) -> Bool {
        date.hasTime ? date.date > now : Calendar.current.startOfDay(for: date.date).addingTimeInterval(86_400) > now
    }
}
