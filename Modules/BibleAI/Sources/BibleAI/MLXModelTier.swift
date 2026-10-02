//
//  MLXModelTier.swift
//  BibleAI
//

import Foundation

/// Which downloadable model a device can run, chosen by physical memory.
/// Thresholds sit below nominal RAM because the OS reports a little less.
public enum MLXModelTier: String, Equatable, Sendable {
    /// Qwen3 1.7B (4-bit), for 6 GB+ devices and Apple-silicon Macs.
    case standard
    /// Qwen3 0.6B (4-bit), for 4 GB iPhones.
    case compact

    static let standardMinimumMemory: UInt64 = 5_905_580_032  // 5.5 GiB
    static let compactMinimumMemory: UInt64 = 3_758_096_384   // 3.5 GiB

    public static func tier(
        physicalMemory: UInt64,
        isSupportedHardware: Bool
    ) -> MLXModelTier? {
        guard isSupportedHardware else { return nil }
        if physicalMemory >= standardMinimumMemory { return .standard }
        if physicalMemory >= compactMinimumMemory { return .compact }
        return nil
    }

    /// The tier for this device, or nil if MLX cannot run here.
    public static var current: MLXModelTier? {
        tier(
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            isSupportedHardware: isSupportedHardware
        )
    }

    /// MLX needs Apple silicon and does not run in the simulator.
    public static var isSupportedHardware: Bool {
        #if arch(arm64) && !targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    public var displayName: String {
        switch self {
        case .standard: "Qwen3 1.7B"
        case .compact: "Qwen3 0.6B"
        }
    }

    /// Bound for chapter context sent with a question.
    public var contextCharacterLimit: Int {
        switch self {
        case .standard: BibleStudyContext.defaultCharacterLimit
        case .compact: 3_000
        }
    }

    /// Bound for the generated answer.
    public var maximumResponseTokens: Int {
        switch self {
        case .standard: 1_024
        case .compact: 512
        }
    }
}
