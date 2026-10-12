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
import Observation
import StoreKit

/// Nextmark Pro's products (PRD P4): one subscription group, plus a lifetime unlock.
/// Universal purchase: the same products on iPhone, iPad and Mac.
public enum ProProduct {
    public static let monthly = "com.nextmark.app.pro.monthly"
    public static let yearly = "com.nextmark.app.pro.yearly"
    public static let lifetime = "com.nextmark.app.pro.lifetime"
    /// In the order the paywall offers them.
    public static let all = [yearly, monthly, lifetime]
}

/// What Free keeps: capture, search and the library stay unlimited, and so does the
/// Weekly Review (Docs/product_strategy.md §5: never hold the user's data hostage).
public enum FreeTier {
    public static let smartGroups = 3
}

/// A transaction, reduced to what decides access.
public struct EntitlementSnapshot: Sendable, Equatable {
    public var productID: String
    public var expiresAt: Date?
    public var revokedAt: Date?
    public var isUpgraded: Bool

    public init(productID: String, expiresAt: Date? = nil, revokedAt: Date? = nil, isUpgraded: Bool = false) {
        self.productID = productID
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.isUpgraded = isUpgraded
    }

    /// One of ours, not refunded, not replaced by an upgrade, and (for a subscription)
    /// not expired.
    func grantsPro(now: Date) -> Bool {
        ProProduct.all.contains(productID)
            && revokedAt == nil
            && !isUpgraded
            && (expiresAt.map { $0 > now } ?? true)
    }

    public static func isPro(_ snapshots: [EntitlementSnapshot], now: Date) -> Bool {
        snapshots.contains { $0.grantsPro(now: now) }
    }

    public static func hasLifetime(_ snapshots: [EntitlementSnapshot], now: Date) -> Bool {
        snapshots.contains { $0.grantsPro(now: now) && $0.productID == ProProduct.lifetime }
    }

    /// A subscription is current, so there's something to manage or cancel (even
    /// alongside a lifetime unlock).
    public static func hasSubscription(_ snapshots: [EntitlementSnapshot], now: Date) -> Bool {
        snapshots.contains { $0.grantsPro(now: now) && $0.productID != ProProduct.lifetime }
    }
}

/// What "Restore Purchases" found.
public enum RestoreOutcome: Sendable, Equatable {
    case restored
    case nothingToRestore
    /// The person dismissed the App Store sign-in.
    case cancelled
}

/// Whether this person has Pro, kept current from StoreKit. The last answer is
/// remembered so the app opens with the right features before StoreKit replies.
@MainActor
@Observable
public final class ProAccess {
    public static let cacheKey = "pro.active"

    public private(set) var isPro: Bool
    public private(set) var hasLifetime = false
    public private(set) var hasSubscription = false
    /// Called when `isPro` changes, so the app can schedule Moments and write Briefs.
    @ObservationIgnored public var onChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(isPro: Bool = UserDefaults.standard.bool(forKey: ProAccess.cacheKey)) {
        self.isPro = isPro
    }

    /// How many smart groups can be kept; nil for no limit.
    public var smartGroupLimit: Int? {
        Self.smartGroupLimit(isPro: isPro)
    }

    public nonisolated static func smartGroupLimit(isPro: Bool) -> Int? {
        isPro ? nil : FreeTier.smartGroups
    }

    /// Reads the current entitlements and keeps listening: renewals, refunds, Ask to
    /// Buy approvals and purchases made on another device arrive as updates.
    public func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    await self?.refresh()
                }
            }
        }
        await refresh()
    }

    public func refresh() async {
        var snapshots: [EntitlementSnapshot] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            snapshots.append(EntitlementSnapshot(
                productID: transaction.productID,
                expiresAt: transaction.expirationDate,
                revokedAt: transaction.revocationDate,
                isUpgraded: transaction.isUpgraded
            ))
        }
        let now = Date()
        hasLifetime = EntitlementSnapshot.hasLifetime(snapshots, now: now)
        hasSubscription = EntitlementSnapshot.hasSubscription(snapshots, now: now)
        set(EntitlementSnapshot.isPro(snapshots, now: now))
    }

    /// A purchase made in the app: finish it, then re-read entitlements.
    public func handle(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await refresh()
    }

    /// "Restore Purchases": asks the App Store for this Apple Account's transactions.
    public func restore() async throws -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        }
        await refresh()
        return isPro ? .restored : .nothingToRestore
    }

    private func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
        guard value != isPro else { return }
        isPro = value
        onChange?(value)
    }
}
