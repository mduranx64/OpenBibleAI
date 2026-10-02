//
//  AIEngineChoiceTests.swift
//  BibleAI
//

import Testing

@testable import BibleAI

struct AIEngineChoiceTests {
    private func choose(
        apple: AppleModelStatus,
        tier: MLXModelTier?,
        hardware: Bool = true,
        installed: Bool = false
    ) -> AIEngineChoice {
        AIEngineChoice.choose(
            apple: apple,
            mlxTier: tier,
            isSupportedHardware: hardware,
            isMLXModelInstalled: installed
        )
    }

    @Test
    func appleModelWinsWheneverItIsAvailable() {
        #expect(choose(apple: .available, tier: .standard, installed: true) == .apple)
        #expect(choose(apple: .available, tier: nil, hardware: false) == .apple)
    }

    @Test
    func installedDownloadedModelIsUsedWhenAppleIsUnavailable() {
        #expect(choose(apple: .unavailable(.deviceNotEligible), tier: .standard, installed: true) == .mlx(.standard))
        #expect(choose(apple: .unavailable(.modelNotReady), tier: .compact, installed: true) == .mlx(.compact))
    }

    @Test
    func missingDownloadIsOfferedOnlyWhereMLXCanRun() {
        #expect(choose(apple: .unavailable(.unsupportedSystem), tier: .compact) == .needsDownload(.compact))
        #expect(choose(apple: .unavailable(.appleIntelligenceNotEnabled), tier: .standard) == .needsDownload(.standard))
    }

    @Test
    func withoutAnyEngineTheReasonExplainsWhatTheUserCanDo() {
        #expect(choose(apple: .unavailable(.appleIntelligenceNotEnabled), tier: nil) == .unavailable(.appleIntelligenceOff))
        #expect(choose(apple: .unavailable(.modelNotReady), tier: nil) == .unavailable(.appleModelPreparing))
        #expect(choose(apple: .unavailable(.deviceNotEligible), tier: nil, hardware: true) == .unavailable(.notEnoughMemory))
        #expect(choose(apple: .unavailable(.unsupportedSystem), tier: nil, hardware: false) == .unavailable(.unsupportedDevice))
    }

    @Test
    func usableReportsWhetherAQuestionCanBeAsked() {
        #expect(AIEngineChoice.apple.isUsable)
        #expect(AIEngineChoice.mlx(.standard).isUsable)
        #expect(!AIEngineChoice.needsDownload(.standard).isUsable)
        #expect(!AIEngineChoice.unavailable(.unsupportedDevice).isUsable)
    }
}
