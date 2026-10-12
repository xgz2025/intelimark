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
import DesignSystem

/// The kinds offered as filters: how people think of their saves, which mixes what
/// was captured (photos, PDFs) with what it is about (products, places…).
enum KindFilter: String, CaseIterable, Identifiable, Hashable {
    case photos, pdfs, articles, products, places, events, recipes, videos, receipts, tickets

    var id: Self { self }

    var captureKind: ItemKind? {
        switch self {
        case .photos: .image
        case .pdfs: .pdf
        default: nil
        }
    }

    var semanticKind: SemanticKind? {
        switch self {
        case .photos, .pdfs: nil
        case .articles: .article
        case .products: .product
        case .places: .place
        case .events: .event
        case .recipes: .recipe
        case .videos: .video
        case .receipts: .receipt
        case .tickets: .ticket
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .photos: "Photos & Screenshots"
        case .pdfs: "PDFs"
        case .articles: "Articles"
        case .products: "Products"
        case .places: "Places"
        case .events: "Events"
        case .recipes: "Recipes"
        case .videos: "Videos"
        case .receipts: "Receipts"
        case .tickets: "Tickets"
        }
    }

    var symbolName: String {
        if let captureKind { return captureKind.symbolName }
        return semanticKind?.symbolName ?? "square.dashed"
    }
}

enum SavedPeriod: String, CaseIterable, Identifiable, Hashable {
    case anyTime, today, pastWeek, pastMonth, pastYear

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .anyTime: "Any Time"
        case .today: "Today"
        case .pastWeek: "Past Week"
        case .pastMonth: "Past Month"
        case .pastYear: "Past Year"
        }
    }

    func interval(endingAt now: Date, calendar: Calendar) -> DateInterval? {
        let start: Date?
        switch self {
        case .anyTime: return nil
        case .today: start = calendar.startOfDay(for: now)
        case .pastWeek: start = calendar.date(byAdding: .day, value: -7, to: now)
        case .pastMonth: start = calendar.date(byAdding: .month, value: -1, to: now)
        case .pastYear: start = calendar.date(byAdding: .year, value: -1, to: now)
        }
        return start.map { DateInterval(start: $0, end: now) }
    }
}

/// The filters chosen in the search UI. Dates are relative ("past week"), so they
/// become a `SearchQuery` only when a search runs.
struct SearchFilters: Equatable {
    var kinds: Set<KindFilter> = []
    var intents: Set<Intent> = []
    var period: SavedPeriod = .anyTime

    var isEmpty: Bool { kinds.isEmpty && intents.isEmpty && period == .anyTime }

    subscript(kind kind: KindFilter) -> Bool {
        get { kinds.contains(kind) }
        set { if newValue { kinds.insert(kind) } else { kinds.remove(kind) } }
    }

    subscript(intent intent: Intent) -> Bool {
        get { intents.contains(intent) }
        set { if newValue { intents.insert(intent) } else { intents.remove(intent) } }
    }

    func query(text: String, now: Date, calendar: Calendar = .current) -> SearchQuery {
        SearchQuery(
            text: text,
            kinds: Set(kinds.compactMap(\.semanticKind)),
            captureKinds: Set(kinds.compactMap(\.captureKind)),
            intents: intents,
            savedWithin: period.interval(endingAt: now, calendar: calendar)
        )
    }

    /// Active filters, in menu order, for the chip row.
    var chips: [FilterChip] {
        var chips: [FilterChip] = KindFilter.allCases.filter { kinds.contains($0) }.map { FilterChip.kind($0) }
        chips += Intent.allCases.filter { intents.contains($0) }.map { FilterChip.intent($0) }
        if period != .anyTime { chips.append(.period(period)) }
        return chips
    }

    mutating func remove(_ chip: FilterChip) {
        switch chip {
        case .kind(let kind): kinds.remove(kind)
        case .intent(let intent): intents.remove(intent)
        case .period: period = .anyTime
        }
    }
}

enum FilterChip: Hashable, Identifiable {
    case kind(KindFilter)
    case intent(Intent)
    case period(SavedPeriod)

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .kind(let kind): kind.title
        case .intent(let intent): intent.title
        case .period(let period): period.title
        }
    }

    var symbolName: String {
        switch self {
        case .kind(let kind): kind.symbolName
        case .intent(let intent): intent.symbolName
        case .period: "calendar"
        }
    }
}
