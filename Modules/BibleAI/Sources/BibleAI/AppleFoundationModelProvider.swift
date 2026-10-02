//
//  AppleFoundationModelProvider.swift
//  BibleAI
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (FoundationModels, iOS/macOS/visionOS 26+).
/// Each question uses a new session: the shared system prompt becomes the
/// session instructions and the user prompt is streamed.
public struct AppleFoundationModelProvider: AIProvider, AIPromptStreaming {
    /// Produces cumulative snapshots for a prompt. Injected in tests.
    typealias SnapshotStream = @Sendable (BibleStudyPrompt) -> AsyncThrowingStream<String, Error>

    private let makeSnapshots: SnapshotStream

    public init() {
        self.makeSnapshots = Self.systemModelSnapshots
    }

    init(makeSnapshots: @escaping SnapshotStream) {
        self.makeSnapshots = makeSnapshots
    }

    public func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        streamResponse(to: BibleStudyPrompt(request))
    }

    public func streamResponse(
        to prompt: BibleStudyPrompt
    ) -> AsyncThrowingStream<String, Error> {
        let snapshots = makeSnapshots(prompt)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulator = StreamDeltaAccumulator()
                do {
                    for try await snapshot in snapshots {
                        try Task.checkCancellation()
                        let delta = accumulator.delta(for: snapshot)
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func systemModelSnapshots(
        _ prompt: BibleStudyPrompt
    ) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let model = prompt.isContentTransformation
                            ? SystemLanguageModel(guardrails: .permissiveContentTransformations)
                            : SystemLanguageModel.default
                        let session = LanguageModelSession(model: model, instructions: prompt.system)
                        let options = GenerationOptions(maximumResponseTokens: 1_024)
                        for try await snapshot in session.streamResponse(
                            to: prompt.user,
                            options: options
                        ) {
                            continuation.yield(snapshot.content)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: mapAppleError(error))
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: AIEngineError.modelUnavailable) }
    }
}

#if canImport(FoundationModels)
/// Maps both the OS 26 `GenerationError` and the OS 27 `LanguageModelError`
/// cases this app can explain; anything else passes through unchanged.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func mapAppleError(_ error: any Error) -> any Error {
    if error is CancellationError { return error }

    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
       let error = error as? LanguageModelError {
        switch error {
        case .contextSizeExceeded: return AIEngineError.contextTooLong
        case .guardrailViolation, .refusal: return AIEngineError.refused
        case .unsupportedLanguageOrLocale: return AIEngineError.unsupportedLanguage
        case .timeout: return AIEngineError.timedOut
        default: return error
        }
    }

    if let error = error as? LanguageModelSession.GenerationError {
        switch error {
        case .exceededContextWindowSize: return AIEngineError.contextTooLong
        case .guardrailViolation, .refusal: return AIEngineError.refused
        case .unsupportedLanguageOrLocale: return AIEngineError.unsupportedLanguage
        case .assetsUnavailable: return AIEngineError.modelUnavailable
        default: return error
        }
    }

    return error
}
#endif
