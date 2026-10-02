//
//  MLXModelProviderTests.swift
//  BibleAI
//

import Foundation
import Testing
import BibleDomain

@testable import BibleAI

struct ThinkBlockFilterTests {
    private func run(_ chunks: [String]) -> String {
        var filter = ThinkBlockFilter()
        return chunks.map { filter.process($0) }.joined() + filter.finish()
    }

    @Test
    func textWithoutThinkBlockPassesThroughUnchanged() {
        #expect(run(["God so ", "loved."]) == "God so loved.")
    }

    @Test
    func leadingThinkBlockIsRemovedWithItsTrailingWhitespace() {
        #expect(run(["<think>\nreasoning\n</think>\n\n", "God so loved."]) == "God so loved.")
    }

    @Test
    func thinkTagsSplitAcrossChunksAreStillRemoved() {
        #expect(run(["<thi", "nk>a", "b</th", "ink>", "\n", "Answer"]) == "Answer")
    }

    @Test
    func emptyThinkBlockIsRemoved() {
        #expect(run(["<think>\n\n</think>\n\nAnswer"]) == "Answer")
    }

    @Test
    func thinkTagLaterInTheAnswerIsKept() {
        #expect(run(["Answer mentions <think> later."]) == "Answer mentions <think> later.")
    }

    @Test
    func unterminatedThinkBlockProducesNothing() {
        #expect(run(["<think>never closed"]) == "")
    }

    @Test
    func shortTextThatOnlyLooksLikeATagPrefixIsFlushedAtTheEnd() {
        #expect(run(["<th"]) == "<th")
    }
}

struct MLXModelProviderTests {
    private func request() throws -> BibleStudyRequest {
        try BibleStudyRequest(
            verse: BibleVerse(
                reference: BibleReference(bookID: "JOH", chapter: 3, verse: 16),
                text: "For God so loved the world"
            ),
            bookName: "John",
            question: "Why?"
        )
    }

    @Test
    func providerSendsTheSharedPromptAndFiltersThinking() async throws {
        let prompts = MLXPromptRecorder()
        let provider = MLXModelProvider { prompt in
            prompts.record(prompt)
            return AsyncThrowingStream { continuation in
                for delta in ["<think>\n\n</think>\n\n", "Because ", "of love."] {
                    continuation.yield(delta)
                }
                continuation.finish()
            }
        }

        var chunks: [String] = []
        for try await chunk in provider.streamResponse(for: try request()) {
            chunks.append(chunk)
        }

        #expect(chunks.joined() == "Because of love.")
        #expect(prompts.prompts == [BibleStudyPrompt(try request())])
    }

    @Test
    func modelSupportRequiresAppleSiliconOutsideTheSimulatorAndEnoughMemory() {
        let gb: UInt64 = 1_073_741_824
        #expect(MLXModelTier.tier(physicalMemory: 16 * gb, isSupportedHardware: true) == .standard)
        #expect(MLXModelTier.tier(physicalMemory: 6 * gb - gb / 2, isSupportedHardware: true) == .standard)
        #expect(MLXModelTier.tier(physicalMemory: 4 * gb - gb / 4, isSupportedHardware: true) == .compact)
        #expect(MLXModelTier.tier(physicalMemory: 3 * gb, isSupportedHardware: true) == nil)
        #expect(MLXModelTier.tier(physicalMemory: 16 * gb, isSupportedHardware: false) == nil)
    }
}

private final class MLXPromptRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BibleStudyPrompt] = []
    var prompts: [BibleStudyPrompt] { lock.withLock { stored } }
    func record(_ prompt: BibleStudyPrompt) { lock.withLock { stored.append(prompt) } }
}
