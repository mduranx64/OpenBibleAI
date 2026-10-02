//
//  AppleFoundationModelProviderTests.swift
//  BibleAI
//

import Foundation
import Testing
import BibleDomain

@testable import BibleAI

struct StreamDeltaAccumulatorTests {
    @Test
    func cumulativeSnapshotsBecomeDeltas() {
        var accumulator = StreamDeltaAccumulator()

        #expect(accumulator.delta(for: "God") == "God")
        #expect(accumulator.delta(for: "God so") == " so")
        #expect(accumulator.delta(for: "God so") == "")
        #expect(accumulator.delta(for: "God so loved") == " loved")
    }

    @Test
    func divergingSnapshotEmitsOnlyTheTextAfterTheCommonPrefix() {
        var accumulator = StreamDeltaAccumulator()
        _ = accumulator.delta(for: "God so lov")

        // Already-emitted text cannot be retracted; only new text is added.
        #expect(accumulator.delta(for: "God so loved") == "ed")
        #expect(accumulator.delta(for: "God gave") == "gave")
    }
}

struct AppleFoundationModelProviderTests {
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

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream { chunks.append(chunk) }
        return chunks
    }

    @Test
    func providerSendsTheSharedPromptAndYieldsDeltas() async throws {
        let recorder = PromptRecorder()
        let provider = AppleFoundationModelProvider { prompt in
            recorder.record(prompt)
            return AsyncThrowingStream { continuation in
                for snapshot in ["Love", "Love moved", "Love moved God."] {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
        }

        let chunks = try await collect(provider.streamResponse(for: request()))

        #expect(chunks == ["Love", " moved", " God."])
        #expect(recorder.prompts == [BibleStudyPrompt(try request())])
    }

    @Test
    func engineErrorsPassThroughUnchanged() async throws {
        let provider = AppleFoundationModelProvider { _ in
            AsyncThrowingStream { $0.finish(throwing: AIEngineError.contextTooLong) }
        }

        await #expect(throws: AIEngineError.contextTooLong) {
            _ = try await collect(provider.streamResponse(for: request()))
        }
    }

    @Test
    func stoppingTheConsumerCancelsTheUnderlyingStream() async throws {
        let cancelled = CancellationFlag()
        let provider = AppleFoundationModelProvider { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("partial")
                continuation.onTermination = { _ in cancelled.set() }
            }
        }

        for try await _ in provider.streamResponse(for: try request()) { break }
        for _ in 0..<200 where !cancelled.isSet { await Task.yield() }

        #expect(cancelled.isSet)
    }

    @Test
    func engineErrorMessagesAreUserFacing() {
        #expect(AIEngineError.contextTooLong.errorDescription?.isEmpty == false)
        #expect(AIEngineError.refused.errorDescription?.isEmpty == false)
        #expect(AIEngineError.unsupportedLanguage.errorDescription?.isEmpty == false)
        #expect(AIEngineError.modelUnavailable.errorDescription?.isEmpty == false)
    }
}

private final class PromptRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BibleStudyPrompt] = []
    var prompts: [BibleStudyPrompt] { lock.withLock { stored } }
    func record(_ prompt: BibleStudyPrompt) { lock.withLock { stored.append(prompt) } }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
