//
//  AIPromptStreaming.swift
//  BibleAI
//

/// An engine that answers an arbitrary system/user prompt as a delta stream.
/// Both on-device providers implement it; `AIProvider` builds its prompt from
/// a `BibleStudyRequest`, while the question pipeline sends its own prompts.
public protocol AIPromptStreaming: Sendable {
    func streamResponse(to prompt: BibleStudyPrompt) -> AsyncThrowingStream<String, Error>
}

extension AIPromptStreaming {
    /// Collects a whole (short) response, e.g. a keyword list.
    public func response(to prompt: BibleStudyPrompt) async throws -> String {
        var text = ""
        for try await delta in streamResponse(to: prompt) {
            text += delta
        }
        return text
    }
}
