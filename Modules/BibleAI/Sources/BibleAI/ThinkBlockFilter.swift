//
//  ThinkBlockFilter.swift
//  BibleAI
//

/// Removes a leading `<think>…</think>` reasoning block (and the whitespace
/// after it) from a delta stream. Qwen3 is asked not to think, but if the
/// template still produces a block it must not appear as part of the answer.
/// Tags may be split across deltas; a `<think>` later in the text is kept.
struct ThinkBlockFilter: Sendable {
    private enum State: Sendable {
        case deciding, thinking, afterThinking, passthrough
    }

    private static let open = "<think>"
    private static let close = "</think>"

    private var state = State.deciding
    private var buffer = ""

    mutating func process(_ delta: String) -> String {
        switch state {
        case .passthrough:
            return delta

        case .deciding:
            buffer += delta
            let candidate = String(buffer.drop(while: \.isWhitespace))
            if candidate.hasPrefix(Self.open) {
                buffer = String(candidate.dropFirst(Self.open.count))
                state = .thinking
                return process("")
            }
            if Self.open.hasPrefix(candidate) {
                return ""  // Could still become `<think>`.
            }
            state = .passthrough
            defer { buffer = "" }
            return buffer

        case .thinking:
            buffer += delta
            guard let range = buffer.range(of: Self.close) else { return "" }
            let rest = String(buffer[range.upperBound...])
            buffer = ""
            state = .afterThinking
            return process(rest)

        case .afterThinking:
            let trimmed = String(delta.drop(while: \.isWhitespace))
            if !trimmed.isEmpty { state = .passthrough }
            return trimmed
        }
    }

    /// Text still held back at the end of the stream.
    mutating func finish() -> String {
        defer { buffer = "" }
        return state == .deciding ? buffer : ""
    }
}
