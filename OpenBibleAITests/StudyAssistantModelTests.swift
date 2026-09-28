//
//  StudyAssistantModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Testing
import BibleAI
import BibleDomain

@testable import OpenBibleAI

@Suite
@MainActor
struct StudyAssistantModelTests {
    @Test
    func answerUpdatesAsChunksArrive() async throws {
        let streamPair =
            AsyncThrowingStream<String, Error>.makeStream()

        let provider = ControlledAIProvider(
            stream: streamPair.stream
        )

        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning, God created the heavens and the earth."
        )

        let model = StudyAssistantModel(provider: provider)

        let askTask = Task {
            await model.ask(
                verse: verse,
                question: "Explain this verse."
            )
        }

        await waitUntil {
            model.state == .streaming
        }

        streamPair.continuation.yield("God is ")

        await waitUntil {
            model.answer == "God is "
        }

        #expect(model.state == .streaming)

        streamPair.continuation.yield("the creator.")

        await waitUntil {
            model.answer == "God is the creator."
        }

        streamPair.continuation.finish()
        await askTask.value

        #expect(model.answer == "God is the creator.")
        #expect(model.state == .completed)
    }

    private func waitUntil(
        _ condition: () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

private struct ControlledAIProvider: AIProvider {
    let stream: AsyncThrowingStream<String, Error>

    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        stream
    }
}
