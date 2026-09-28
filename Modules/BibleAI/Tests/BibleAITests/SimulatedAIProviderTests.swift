//
//  SimulatedAIProviderTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Testing
import BibleAI
import BibleDomain

@Suite
struct SimulatedAIProviderTests {
    @Test
    func providerStreamsChunksInOrder() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning, God created the heavens and the earth."
        )

        let request = try BibleStudyRequest(
            verse: verse,
            question: "Explain this verse."
        )

        let provider = SimulatedAIProvider(
            chunks: [
                "God ",
                "is the ",
                "creator."
            ],
            delay: .zero
        )

        var receivedChunks: [String] = []

        for try await chunk in provider.streamResponse(
            for: request
        ) {
            receivedChunks.append(chunk)
        }

        #expect(
            receivedChunks == [
                "God ",
                "is the ",
                "creator."
            ]
        )
    }
}
