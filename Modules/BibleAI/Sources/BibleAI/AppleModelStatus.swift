//
//  AppleModelStatus.swift
//  BibleAI
//

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can be used, and if not, why.
public enum AppleModelStatus: Equatable, Sendable {
    case available
    case unavailable(Reason)

    public enum Reason: Equatable, Sendable {
        /// The device can never run Apple Intelligence.
        case deviceNotEligible
        /// Supported device, but Apple Intelligence is turned off.
        case appleIntelligenceNotEnabled
        /// Apple Intelligence is on but the model is still downloading/preparing.
        case modelNotReady
        /// Older OS (before 26) or a platform without FoundationModels.
        case unsupportedSystem
        /// A reason added by a newer OS.
        case other
    }

    public static var current: AppleModelStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(.deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(.appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady):
                return .unavailable(.modelNotReady)
            case .unavailable:
                return .unavailable(.other)
            }
        }
        #endif
        return .unavailable(.unsupportedSystem)
    }
}
