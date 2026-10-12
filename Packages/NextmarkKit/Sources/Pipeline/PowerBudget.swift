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

/// How much background enrichment (page fetches, text recognition, the on-device
/// model) the device can take right now (Docs/architecture.md §5.1). Saving and
/// ingesting captures always run; only enrichment slows down or waits.
public enum PowerBudget: Sendable, Equatable {
    /// Batch after batch.
    case full
    /// Low Power Mode, or the device is hot: a few jobs at a time, minutes apart.
    case reduced
    /// The device is critically hot: wait until it cools down.
    case paused

    public static var current: PowerBudget {
        budget(thermal: ProcessInfo.processInfo.thermalState, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    public static func budget(thermal: ProcessInfo.ThermalState, lowPower: Bool) -> PowerBudget {
        switch thermal {
        case .critical: .paused
        case .serious: .reduced
        default: lowPower ? .reduced : .full
        }
    }

    /// Jobs per pass.
    public var batchSize: Int {
        switch self {
        case .full: 25
        case .reduced: 5
        case .paused: 0
        }
    }

    /// The soonest the pipeline runs again on its own, after a pass.
    public var minimumWakeDelay: TimeInterval {
        switch self {
        case .full: 5
        case .reduced, .paused: 15 * 60
        }
    }
}
