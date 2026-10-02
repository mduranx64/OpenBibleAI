//
//  AIEngineChoice.swift
//  BibleAI
//

/// Which engine answers study questions on this device right now.
public enum AIEngineChoice: Equatable, Sendable {
    /// Apple's on-device model.
    case apple
    /// The downloaded MLX model for this device's tier.
    case mlx(MLXModelTier)
    /// MLX can run here, but the tier's model is not downloaded yet.
    case needsDownload(MLXModelTier)
    /// No engine can be used; the reason tells the user what (if anything) helps.
    case unavailable(UnavailableReason)

    public enum UnavailableReason: Equatable, Sendable {
        /// Turning on Apple Intelligence would enable AI.
        case appleIntelligenceOff
        /// Apple's model is still downloading/preparing.
        case appleModelPreparing
        /// Apple silicon, but too little memory for any downloadable model.
        case notEnoughMemory
        /// Intel Mac, simulator, or an older device without Apple Intelligence.
        case unsupportedDevice
    }

    public var isUsable: Bool {
        switch self {
        case .apple, .mlx: true
        case .needsDownload, .unavailable: false
        }
    }

    /// Apple's model first; then the downloaded model; then explain.
    public static func choose(
        apple: AppleModelStatus,
        mlxTier: MLXModelTier?,
        isSupportedHardware: Bool,
        isMLXModelInstalled: Bool
    ) -> AIEngineChoice {
        if apple == .available { return .apple }

        if let mlxTier {
            return isMLXModelInstalled ? .mlx(mlxTier) : .needsDownload(mlxTier)
        }

        switch apple {
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceOff)
        case .unavailable(.modelNotReady):
            return .unavailable(.appleModelPreparing)
        default:
            return .unavailable(isSupportedHardware ? .notEnoughMemory : .unsupportedDevice)
        }
    }
}
