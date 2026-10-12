//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import Testing
@testable import Grouping

struct GroupAssignerTests {
    let centroids = [
        GroupCentroid(groupID: "kyoto", vector: [1, 0, 0], memberCount: 4),
        GroupCentroid(groupID: "desk", vector: [0, 1, 0], memberCount: 2),
    ]

    @Test func suggestsTheMostSimilarGroupAboveThreshold() {
        let suggestion = GroupAssigner(threshold: 0.7).suggestion(for: [0.9, 0.1, 0], among: centroids)
        #expect(suggestion?.groupID == "kyoto")
    }

    @Test func suggestsNothingBelowThreshold() {
        #expect(GroupAssigner(threshold: 0.9).suggestion(for: [1, 1, 0], among: centroids) == nil)
    }

    @Test func centroidIsARunningMean() {
        let updated = GroupCentroid(groupID: "g", vector: [2, 2], memberCount: 1).adding([4, 0])
        #expect(updated.vector == [3, 1])
        #expect(updated.memberCount == 2)
    }
}
