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
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple Intelligence's on-device model can be used right now. Nextmark works
/// without it everywhere (Docs/architecture.md §5.3): its built-in rules write titles,
/// summaries and Briefs, and the model improves them once it's there.
public enum IntelligenceStatus: Sendable, Equatable, CustomStringConvertible {
    case available
    /// Apple Intelligence is off, or not offered in the person's country or region.
    case notEnabled
    /// This iPhone, iPad or Mac can't run Apple Intelligence.
    case deviceNotEligible
    /// It's on, and its model is still downloading or getting ready.
    case preparing
    /// This OS has no on-device model.
    case unsupported

    public static var current: IntelligenceStatus {
        #if canImport(FoundationModels)
        // `if case` rather than `switch`: the framework may add reasons later.
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .available }
        if case .unavailable(.appleIntelligenceNotEnabled) = availability { return .notEnabled }
        if case .unavailable(.deviceNotEligible) = availability { return .deviceNotEligible }
        if case .unavailable(.modelNotReady) = availability { return .preparing }
        return .unsupported
        #else
        return .unsupported
        #endif
    }

    public var isAvailable: Bool { self == .available }

    /// A few words for a status line.
    public var description: String {
        switch self {
        case .available: String(localized: "On")
        case .notEnabled: String(localized: "Off")
        case .deviceNotEligible: String(localized: "Not available on this device")
        case .preparing: String(localized: "Getting ready")
        case .unsupported: String(localized: "Not available")
        }
    }

    /// What it means for Nextmark, and what the person can do about it.
    public var explanation: String {
        switch self {
        case .available:
            String(localized: "Titles, summaries, photo descriptions and Briefs are written on this device by Apple Intelligence.")
        case .notEnabled:
            String(localized: "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri for richer summaries and Briefs. Where it isn't offered in your country or region, Nextmark's built-in rules write them instead, and everything else works the same.")
        case .deviceNotEligible, .unsupported:
            String(localized: "Nextmark's built-in rules write titles, summaries and Briefs on this device. Saving, search, groups, reminders and sync work the same.")
        case .preparing:
            String(localized: "Apple Intelligence is downloading its model. Until it's ready, Nextmark's built-in rules write summaries, and they're improved automatically afterwards.")
        }
    }
}
