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
@testable import Moments

struct MomentPlannerTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func movesQuietHourMomentsToTheMorning() {
        let planner = MomentPlanner(calendar: calendar)
        let late = MomentCandidate(targetID: "a", fireDate: date(10, 23, 30), reason: .deadline)
        let early = MomentCandidate(targetID: "b", fireDate: date(10, 6), reason: .deadline)
        let plan = planner.plan([late, early], now: date(9, 12))
        #expect(plan.map(\.fireDate) == [date(10, 8), date(11, 8)])
    }

    @Test func keepsTheHighestPriorityWithinTheDailyBudget() {
        let planner = MomentPlanner(policy: MomentPolicy(maxPerDay: 2), calendar: calendar)
        let candidates = (0..<4).map { index in
            MomentCandidate(targetID: "\(index)", fireDate: date(10, 9 + index), reason: .eventStart, priority: index)
        }
        let plan = planner.plan(candidates, now: date(9, 12))
        #expect(plan.map(\.targetID) == ["2", "3"])
    }

    @Test func quietHoursNeverPushAMomentPastItsEvent() {
        let planner = MomentPlanner(calendar: calendar)
        // Three hours before a 1 AM show lands at 10 PM, in quiet hours; 8 AM is too late.
        let late = MomentCandidate(targetID: "a", fireDate: date(9, 22), reason: .eventStart, latest: date(10, 1))
        let fine = MomentCandidate(targetID: "b", fireDate: date(9, 23), reason: .deadline, latest: date(11, 0))
        #expect(planner.plan([late, fine], now: date(9, 12)).map(\.targetID) == ["b"])
    }

    @Test func deliveredAndSnoozedMomentsCountAgainstTheDay() {
        let planner = MomentPlanner(policy: MomentPolicy(maxPerDay: 3), calendar: calendar)
        let candidates = (0..<3).map { MomentCandidate(targetID: "\($0)", fireDate: date(10, 12 + $0), reason: .deadline) }
        let plan = planner.plan(candidates, now: date(10, 11), committed: [date(10, 9), date(10, 10), date(11, 9)])
        #expect(plan.map(\.targetID) == ["0"])
    }

    @Test func dropsPastMomentsAndCapsPending() {
        let planner = MomentPlanner(policy: MomentPolicy(maxPerDay: 10, maxPending: 3), calendar: calendar)
        let past = MomentCandidate(targetID: "past", fireDate: date(1, 12), reason: .deadline)
        let future = (0..<5).map { MomentCandidate(targetID: "f\($0)", fireDate: date(10 + $0, 12), reason: .deadline) }
        let plan = planner.plan([past] + future, now: date(5, 12))
        #expect(plan.map(\.targetID) == ["f0", "f1", "f2"])
    }
}
