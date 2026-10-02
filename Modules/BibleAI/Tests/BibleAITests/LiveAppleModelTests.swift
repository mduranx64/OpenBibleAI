//
//  LiveAppleModelTests.swift
//  BibleAI
//

import Foundation
import Testing
import BibleDomain

@testable import BibleAI

/// Real Apple on-device model check, separate from the mocked tests.
/// Skipped unless `OPENBIBLE_LIVE_APPLE=1`; needs Apple Intelligence on.
/// Prints the answer for a human to read; asserts only that it streams.
struct LiveAppleModelTests {
    private static let enabled =
        ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_APPLE"] == "1"

    @Test(.enabled(if: LiveAppleModelTests.enabled))
    func appleModelStreamsAnAnswerWithChapterContext() async throws {
        #expect(AppleModelStatus.current == .available)

        func verse(_ number: Int, _ text: String) throws -> BibleVerse {
            try BibleVerse(reference: BibleReference(bookID: "JOH", chapter: 3, verse: number), text: text)
        }
        let context = try [
            verse(15, "That whosoever believeth in him should not perish, but have eternal life."),
            verse(16, "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
            verse(17, "For God sent not his Son into the world to condemn the world; but that the world through him might be saved.")
        ]
        let request = try BibleStudyRequest(
            verse: context[1],
            bookName: "John",
            context: context,
            question: "In one or two sentences, what does this verse say about God's motive?"
        )

        let clock = ContinuousClock()
        let start = clock.now
        var chunks: [String] = []
        for try await chunk in AppleFoundationModelProvider().streamResponse(for: request) {
            chunks.append(chunk)
        }
        let answer = chunks.joined()

        print("""

        === OPENBIBLE LIVE APPLE MODEL ===
        chunks: \(chunks.count), elapsed: \(clock.now - start)
        \(answer)
        === END ===

        """)

        #expect(chunks.count > 1, "Expected streamed deltas, not one block")
        #expect(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
