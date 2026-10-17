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

/// `App/Nextmark.storekit` (Xcode's local store) offers exactly the products the
/// app sells, with the one-week trial on the subscriptions. Read as a file, so it
/// runs anywhere, CI included.
struct StoreKitConfigurationFileTests {
    struct Configuration: Decodable {
        struct Product: Decodable {
            let productID: String
            let type: String
        }
        struct Offer: Decodable {
            let paymentMode: String
            let subscriptionPeriod: String
        }
        struct Subscription: Decodable {
            let productID: String
            let type: String
            let recurringSubscriptionPeriod: String
            let introductoryOffer: Offer?
        }
        struct Group: Decodable {
            let subscriptions: [Subscription]
        }
        let products: [Product]
        let subscriptionGroups: [Group]
    }

    static let url = URL(filePath: #filePath)
        .deletingLastPathComponent()      // StoreTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // NextmarkKit
        .deletingLastPathComponent()      // Packages
        .deletingLastPathComponent()      // repository
        .appending(path: "App/Nextmark.storekit")

    @Test func offersExactlyTheProductsTheAppSells() throws {
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: Self.url))
        let subscriptions = configuration.subscriptionGroups.flatMap(\.subscriptions)
        let ids = Set(configuration.products.map(\.productID) + subscriptions.map(\.productID))
        #expect(ids == Set(ProProduct.all))
        #expect(configuration.products.map(\.type) == ["NonConsumable"])
        #expect(configuration.products.map(\.productID) == [ProProduct.lifetime])
    }

    @Test func subscriptionsRenewMonthlyAndYearlyAfterAOneWeekTrial() throws {
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: Self.url))
        let subscriptions = Dictionary(
            uniqueKeysWithValues: configuration.subscriptionGroups.flatMap(\.subscriptions).map { ($0.productID, $0) }
        )
        #expect(subscriptions[ProProduct.monthly]?.recurringSubscriptionPeriod == "P1M")
        #expect(subscriptions[ProProduct.yearly]?.recurringSubscriptionPeriod == "P1Y")
        for id in [ProProduct.monthly, ProProduct.yearly] {
            #expect(subscriptions[id]?.type == "RecurringSubscription")
            #expect(subscriptions[id]?.introductoryOffer?.paymentMode == "free")
            #expect(subscriptions[id]?.introductoryOffer?.subscriptionPeriod == "P1W")
        }
    }
}
