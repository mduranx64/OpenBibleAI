//
//  AIResponseCollectorTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Testing
import BibleAI
import BibleDomain

@Suite
struct AIResponseCollectorTests {
    @Test
    func collectorCombinesStreamedChunks() async throws {
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

        let provider = StubAIProvider(
            chunks: [
                "This verse ",
                "introduces God ",
                "as the creator."
            ]
        )

        let collector = AIResponseCollector(provider: provider)

        let response = try await collector.response(
            for: request
        )

        #expect(
            response ==
                "This verse introduces God as the creator."
        )
    }
    
    @Test
    func collectorRejectsEmptyResponse() async throws {
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

        let provider = StubAIProvider(chunks: [])
        let collector = AIResponseCollector(provider: provider)

        await #expect(
            throws: AIResponseCollector.ResponseError.emptyResponse
        ) {
            try await collector.response(for: request)
        }
    }
}

private struct StubAIProvider: AIProvider {
    let chunks: [String]

    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }

            continuation.finish()
        }
    }
}
