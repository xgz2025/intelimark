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
import Testing
@testable import Model

struct FactMergeTests {
    let day = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func structuredDatesComeFirstAndDuplicatesAreDropped() {
        let structured = [ItemDate(date: day, hasTime: true, role: .eventStart, source: .structured)]
        let inferred = [
            ItemDate(date: day.addingTimeInterval(60), hasTime: true, role: .eventStart, source: .model),   // same day + role
            ItemDate(date: day.addingTimeInterval(120), hasTime: false, role: .mentioned, source: .detector), // same day, mention
            ItemDate(date: day.addingTimeInterval(3 * 86_400), hasTime: false, role: .deadline, source: .model),
        ]
        let merged = FactMerge.dates(structured: structured, inferred: inferred)
        #expect(merged.map(\.source) == [.structured, .model])
        #expect(merged.last?.role == .deadline)
    }

    @Test func placesAreDedupedByName() {
        let merged = FactMerge.places(
            structured: [ItemPlace(name: "Budokan", source: .structured)],
            inferred: [ItemPlace(name: "BUDOKAN", source: .model), ItemPlace(name: "Ichiran", source: .model)]
        )
        #expect(merged.map(\.name) == ["Budokan", "Ichiran"])
    }

    @Test func schemaEventsBecomeDatesAndPlaces() {
        let fields = TypedFields(event: EventFields(name: "Concert", startDate: day, venue: "Budokan", address: "Tokyo"))
        #expect(fields.structuredDates.map(\.role) == [.eventStart])
        #expect(fields.structuredPlaces == [ItemPlace(name: "Budokan", address: "Tokyo", source: .structured)])
    }

    @Test func dateOnlyValuesHaveNoTimeOfDay() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let midnight = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        #expect(FactMerge.hasTimeOfDay(midnight, calendar: tokyo) == false)
        #expect(FactMerge.hasTimeOfDay(midnight.addingTimeInterval(3_600), calendar: tokyo))
    }
}
