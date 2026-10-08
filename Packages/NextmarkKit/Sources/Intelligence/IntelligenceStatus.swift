import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum IntelligenceStatus: Sendable, Equatable, CustomStringConvertible {
    case available
    case unavailable(reason: String)
    case unsupported

    public static var current: IntelligenceStatus {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .available }
        if case .unavailable(let reason) = availability { return .unavailable(reason: String(describing: reason)) }
        return .unsupported
        #else
        return .unsupported
        #endif
    }

    public var description: String {
        switch self {
        case .available: String(localized: "Available")
        case .unavailable(let reason): String(localized: "Unavailable (\(reason))")
        case .unsupported: String(localized: "Not supported on this device")
        }
    }
}
