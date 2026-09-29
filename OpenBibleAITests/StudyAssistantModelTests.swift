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
    
    @Test
    func latestQuestionIgnoresChunksFromOlderStream() async throws {
        let firstPair =
            AsyncThrowingStream<String, Error>.makeStream()

        let secondPair =
            AsyncThrowingStream<String, Error>.makeStream()

        let provider = TwoStreamAIProvider(
            firstQuestion: "First question",
            firstStream: firstPair.stream,
            secondStream: secondPair.stream
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

        let firstTask = Task {
            await model.ask(
                verse: verse,
                question: "First question"
            )
        }

        await waitUntil {
            model.state == .streaming
        }

        let secondTask = Task {
            await model.ask(
                verse: verse,
                question: "Second question"
            )
        }

        secondPair.continuation.yield("New answer.")
        secondPair.continuation.finish()

        await secondTask.value

        #expect(model.answer == "New answer.")
        #expect(model.state == .completed)

        firstPair.continuation.yield("Old answer.")
        firstPair.continuation.finish()

        await firstTask.value

        #expect(model.answer == "New answer.")
        #expect(model.state == .completed)
    }
    
    @Test
    func displaysOllamaServerMessageOnFailure() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning, God created the heavens and the earth."
        )

        let model = StudyAssistantModel(
            provider: OllamaErrorAIProvider()
        )

        await model.ask(
            verse: verse,
            question: "Explain this verse."
        )

        #expect(
            model.state == .failed(
                "model 'missing-model' not found"
            )
        )
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

private struct TwoStreamAIProvider: AIProvider {
    let firstQuestion: String
    let firstStream: AsyncThrowingStream<String, Error>
    let secondStream: AsyncThrowingStream<String, Error>

    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        if request.question == firstQuestion {
            firstStream
        } else {
            secondStream
        }
    }
}

private struct OllamaErrorAIProvider: AIProvider {
    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing:
                    OllamaProvider.ProviderError.serverMessage(
                        "model 'missing-model' not found"
                    )
            )
        }
    }
}
