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
import Model

struct TimeLimitTests {
    @Test func fastWorkReturnsItsResult() async throws {
        #expect(try await withTimeLimit(5) { 42 } == 42)
    }

    @Test func slowWorkGivesUpOnTime() async {
        let start = Date()
        await #expect(throws: TimeLimitExceeded.self) {
            // Ignores cancellation, like a framework call that never checks.
            try await withTimeLimit(0.2) {
                let end = Date().addingTimeInterval(2)
                while Date() < end { await Task.yield() }
                return 1
            }
        }
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    @Test func errorsArePassedOn() async {
        struct Failure: Error {}
        await #expect(throws: Failure.self) {
            try await withTimeLimit(5) { () async throws -> Int in throw Failure() }
        }
    }
}
