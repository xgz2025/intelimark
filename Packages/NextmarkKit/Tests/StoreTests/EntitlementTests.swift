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
@testable import Store

struct EntitlementTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func nothingBoughtIsFree() {
        #expect(!EntitlementSnapshot.isPro([], now: now))
        #expect(ProAccess.smartGroupLimit(isPro: false) == FreeTier.smartGroups)
        #expect(ProAccess.smartGroupLimit(isPro: true) == nil)
    }

    @Test func aLiveSubscriptionIsPro() {
        let yearly = EntitlementSnapshot(productID: ProProduct.yearly, expiresAt: now.addingTimeInterval(86_400))
        #expect(EntitlementSnapshot.isPro([yearly], now: now))
        let lapsed = EntitlementSnapshot(productID: ProProduct.monthly, expiresAt: now.addingTimeInterval(-1))
        #expect(!EntitlementSnapshot.isPro([lapsed], now: now))
    }

    @Test func lifetimeNeverExpires() {
        #expect(EntitlementSnapshot.isPro([EntitlementSnapshot(productID: ProProduct.lifetime)], now: now))
    }

    @Test func refundsAndUpgradesDontCount() {
        let refunded = EntitlementSnapshot(productID: ProProduct.lifetime, revokedAt: now.addingTimeInterval(-60))
        let upgraded = EntitlementSnapshot(productID: ProProduct.monthly, expiresAt: now.addingTimeInterval(86_400), isUpgraded: true)
        #expect(!EntitlementSnapshot.isPro([refunded, upgraded], now: now))
        let yearly = EntitlementSnapshot(productID: ProProduct.yearly, expiresAt: now.addingTimeInterval(86_400))
        #expect(EntitlementSnapshot.isPro([upgraded, yearly], now: now))
    }

    @Test func otherProductsDontUnlockPro() {
        #expect(!EntitlementSnapshot.isPro([EntitlementSnapshot(productID: "com.example.other")], now: now))
    }
}
