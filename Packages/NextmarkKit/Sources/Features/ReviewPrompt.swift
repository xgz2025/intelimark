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
import StoreKit
import SwiftUI

/// Asks for an App Store rating at a good moment: right after something went well
/// (a Weekly Review finished, every action on a save done), once the person has used
/// Nextmark on a few days, and at most once a version and every four months. The
/// system decides whether to show it, and shows it at most three times a year.
public enum ReviewPrompt {
    static let activeDaysKey = "review.activeDays"
    static let lastActiveDayKey = "review.lastActiveDay"
    static let successesKey = "review.successes"
    static let lastAskedKey = "review.lastAsked"
    static let lastAskedVersionKey = "review.lastAskedVersion"

    static let minimumActiveDays = 3
    static let minimumSuccesses = 2
    static let minimumInterval: TimeInterval = 120 * 86_400

    /// Counts the days Nextmark is used. Call when it comes to the foreground.
    public static func noteActiveDay(now: Date = Date(), defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if let last = defaults.object(forKey: lastActiveDayKey) as? Date, calendar.isDate(last, inSameDayAs: today) { return }
        defaults.set(today, forKey: lastActiveDayKey)
        defaults.set(defaults.integer(forKey: activeDaysKey) + 1, forKey: activeDaysKey)
    }

    /// Records something that went well; true when it's a good moment to ask now.
    static func noteSuccess(now: Date = Date(), version: String?, defaults: UserDefaults = .standard) -> Bool {
        let successes = defaults.integer(forKey: successesKey) + 1
        defaults.set(successes, forKey: successesKey)
        guard shouldAsk(
            activeDays: defaults.integer(forKey: activeDaysKey),
            successes: successes,
            lastAsked: defaults.object(forKey: lastAskedKey) as? Date,
            lastAskedVersion: defaults.string(forKey: lastAskedVersionKey),
            version: version,
            now: now
        ) else { return false }
        defaults.set(now, forKey: lastAskedKey)
        defaults.set(version, forKey: lastAskedVersionKey)
        return true
    }

    static func shouldAsk(
        activeDays: Int, successes: Int, lastAsked: Date?, lastAskedVersion: String?, version: String?, now: Date
    ) -> Bool {
        guard activeDays >= minimumActiveDays, successes >= minimumSuccesses else { return false }
        if let version, version == lastAskedVersion { return false }
        if let lastAsked, now.timeIntervalSince(lastAsked) < minimumInterval { return false }
        return true
    }

    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

extension View {
    /// Asks for a rating when `success` changes to true, if it's a good moment
    /// (`ReviewPrompt`). A short pause lets the success show first.
    func requestsReview(after success: Bool) -> some View {
        modifier(ReviewRequest(success: success))
    }
}

private struct ReviewRequest: ViewModifier {
    let success: Bool
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        // `initial`: a "done" screen can appear already done.
        content.onChange(of: success, initial: true) { _, succeeded in
            guard succeeded, ReviewPrompt.noteSuccess(version: ReviewPrompt.currentVersion) else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
            }
        }
    }
}
