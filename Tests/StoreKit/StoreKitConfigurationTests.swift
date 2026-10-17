//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import XCTest
import StoreKit
import StoreKitTest

/// Laterwise Pro's in-app purchases against `App/Nextmark.storekit`, with StoreKit
/// Testing: no App Store account, no network. Runs in the iOS app (Docs/testing.md).
@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    static let monthly = "com.veloworkspaces.nextmark.pro.monthly"
    static let yearly = "com.veloworkspaces.nextmark.pro.yearly"
    static let lifetime = "com.veloworkspaces.nextmark.pro.lifetime"

    /// A fresh store: no purchases, no dialogs. Loaded from this test bundle's copy of
    /// the configuration, and given a moment to start serving it.
    private func makeSession() async throws -> SKTestSession {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Nextmark", withExtension: "storekit"),
            "Nextmark.storekit isn't in the test bundle"
        )
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        try await Task.sleep(for: .milliseconds(500))
        return session
    }

    func testProductsLoadWithAOneWeekTrialOnSubscriptions() async throws {
        let session = try await makeSession()
        let products = try await Product.products(for: [Self.monthly, Self.yearly, Self.lifetime])
        XCTAssertEqual(Set(products.map(\.id)), [Self.monthly, Self.yearly, Self.lifetime])
        for id in [Self.monthly, Self.yearly] {
            let product = try XCTUnwrap(products.first { $0.id == id })
            XCTAssertEqual(product.type, .autoRenewable)
            let trial = try XCTUnwrap(product.subscription?.introductoryOffer, "\(id) has no trial")
            XCTAssertEqual(trial.paymentMode, .freeTrial)
            XCTAssertEqual(trial.period.unit, .week)
            XCTAssertEqual(trial.period.value, 1)
        }
        XCTAssertEqual(products.first { $0.id == Self.lifetime }?.type, .nonConsumable)
        _ = session
    }

    func testASubscriptionUnlocksProUntilItExpires() async throws {
        let session = try await makeSession()
        let transaction = try await session.buyProduct(identifier: Self.yearly, options: [])
        let entitled = await entitlements(eventually: { $0.contains(Self.yearly) })
        XCTAssertTrue(entitled.contains(Self.yearly))

        // Cancelled first: with auto-renew on, the test store renews it straight away.
        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        try session.expireSubscription(productIdentifier: Self.yearly)
        let afterExpiry = await entitlements(eventually: { !$0.contains(Self.yearly) })
        XCTAssertFalse(afterExpiry.contains(Self.yearly))
    }

    func testARefundedLifetimeUnlockNoLongerCounts() async throws {
        let session = try await makeSession()
        let transaction = try await session.buyProduct(identifier: Self.lifetime, options: [])
        let entitled = await entitlements(eventually: { $0.contains(Self.lifetime) })
        XCTAssertTrue(entitled.contains(Self.lifetime))

        try session.refundTransaction(identifier: UInt(transaction.id))
        let afterRefund = await entitlements(eventually: { !$0.contains(Self.lifetime) })
        XCTAssertFalse(afterRefund.contains(Self.lifetime))
    }

    /// The product IDs that unlock Pro now, by the app's rule (`ProAccess`): not
    /// refunded, not expired. Waits a moment for StoreKit to catch up with a purchase,
    /// an expiry or a refund.
    private func entitlements(eventually condition: (Set<String>) -> Bool) async -> Set<String> {
        var ids: Set<String> = []
        for _ in 0..<20 {
            ids = []
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.revocationDate == nil,
                   transaction.expirationDate.map({ $0 > Date() }) ?? true {
                    ids.insert(transaction.productID)
                }
            }
            if condition(ids) { return ids }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return ids
    }
}
