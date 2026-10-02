//
//  MLXModelProvider.swift
//  BibleAI
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A downloaded model run in-process with MLX Swift. Each question uses a new
/// `ChatSession` with the shared system prompt as instructions; thinking is
/// turned off and any leading `<think>` block is filtered out.
public struct MLXModelProvider: AIProvider, AIPromptStreaming {
    /// Produces answer deltas for a prompt. Injected in tests.
    typealias DeltaStream = @Sendable (BibleStudyPrompt) -> AsyncThrowingStream<String, Error>

    private let makeDeltas: DeltaStream

    public init(engine: MLXModelEngine, maximumResponseTokens: Int) {
        self.makeDeltas = { prompt in
            engine.stream(prompt, maximumResponseTokens: maximumResponseTokens)
        }
    }

    init(makeDeltas: @escaping DeltaStream) {
        self.makeDeltas = makeDeltas
    }

    public func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        streamResponse(to: BibleStudyPrompt(request))
    }

    public func streamResponse(
        to prompt: BibleStudyPrompt
    ) -> AsyncThrowingStream<String, Error> {
        let deltas = makeDeltas(prompt)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var filter = ThinkBlockFilter()
                do {
                    for try await delta in deltas {
                        try Task.checkCancellation()
                        let visible = filter.process(delta)
                        if !visible.isEmpty { continuation.yield(visible) }
                    }
                    let rest = filter.finish()
                    if !rest.isEmpty { continuation.yield(rest) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Owns the loaded model so it is read from disk once and shared across
/// questions. Loading can take seconds; `unload()` frees the memory.
public actor MLXModelEngine {
    private let directory: URL
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    public init(directory: URL) {
        self.directory = directory
        // Keep MLX's buffer cache small; it is a cache, not model memory.
        Memory.cacheLimit = 64 * 1_024 * 1_024
    }

    public var isLoaded: Bool { container != nil }

    /// Loads the model if needed (e.g. to show "Preparing model…" early).
    public func prepare() async throws {
        _ = try await loadedContainer()
    }

    public func unload() {
        loading?.cancel()
        loading = nil
        container = nil
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }
        if let loading { return try await loading.value }

        let directory = self.directory
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(
                from: directory,
                using: TransformersTokenizerLoader()
            )
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        container = loaded
        return loaded
    }

    nonisolated func stream(
        _ prompt: BibleStudyPrompt,
        maximumResponseTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await self.loadedContainer()
                    let session = ChatSession(
                        container,
                        instructions: prompt.system,
                        generateParameters: GenerateParameters(maxTokens: maximumResponseTokens),
                        additionalContext: ["enable_thinking": false]
                    )
                    for try await delta in session.streamResponse(to: prompt.user) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
