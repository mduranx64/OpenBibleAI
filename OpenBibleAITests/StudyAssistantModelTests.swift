//
//  StudyAssistantModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation
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
    
    private func verse(_ number: Int, text: String? = nil) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(bookID: "JOH", chapter: 3, verse: number),
            text: text ?? "Text of verse \(number)."
        )
    }

    @Test
    func askSendsBookNameAndBoundedChapterContextToTheProvider() async throws {
        let recorder = RequestRecorder()
        let model = StudyAssistantModel(
            provider: RecordingAIProvider(recorder: recorder, answer: "ok")
        )
        // 40 verses of 300 characters (12,000 total) exceed the 6,000 bound.
        let chapter = try (1...40).map {
            try verse($0, text: String(repeating: "x", count: 300))
        }

        await model.ask(
            verse: try verse(20, text: String(repeating: "x", count: 300)),
            bookName: "John",
            chapterVerses: chapter,
            question: "Why?"
        )

        let request = try #require(recorder.requests.first)
        #expect(request.bookName == "John")
        #expect(request.context.contains { $0.reference.verse == 20 })
        #expect(request.context.reduce(0) { $0 + $1.text.count } <= BibleStudyContext.defaultCharacterLimit)
        #expect(request.context.count == 20)
        let numbers = request.context.map(\.reference.verse)
        #expect(numbers == Array(numbers[0]...numbers[numbers.count - 1]))
    }

    @Test
    func askWithoutChapterVersesSendsNoContext() async throws {
        let recorder = RequestRecorder()
        let model = StudyAssistantModel(
            provider: RecordingAIProvider(recorder: recorder, answer: "ok")
        )

        await model.ask(verse: try verse(16), question: "Why?")

        let request = try #require(recorder.requests.first)
        #expect(request.context.isEmpty)
        #expect(request.bookName == nil)
    }

    @Test
    func answerBelongsToTheVerseItWasAskedAbout() async throws {
        let model = StudyAssistantModel(
            provider: ImmediateAIProvider(answer: "About sixteen.")
        )
        let asked = try verse(16)
        let other = try verse(17)

        await model.ask(verse: asked, question: "Why?")

        #expect(model.answerReference == asked.reference)
        #expect(model.answer(for: asked.reference) == "About sixteen.")
        #expect(model.answer(for: other.reference) == "")
    }

    @Test
    func resetClearsAnswerAndDropsChunksFromAnInFlightStream() async throws {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        let model = StudyAssistantModel(
            provider: ControlledAIProvider(stream: pair.stream)
        )
        let asked = try verse(16)

        let task = Task { await model.ask(verse: asked, question: "Why?") }
        await waitUntil { model.state == .streaming }
        pair.continuation.yield("Partial ")
        await waitUntil { model.answer == "Partial " }

        model.reset()

        #expect(model.answer == "")
        #expect(model.answerReference == nil)
        #expect(model.state == .idle)

        pair.continuation.yield("late chunk")
        pair.continuation.finish()
        await task.value

        #expect(model.answer == "")
        #expect(model.answerReference == nil)
        #expect(model.state == .idle)
    }

    @Test
    func contextLimitFollowsTheEngineInUse() async throws {
        let recorder = RequestRecorder()
        let model = StudyAssistantModel(
            makeProvider: { RecordingAIProvider(recorder: recorder, answer: "ok") },
            contextCharacterLimit: { 900 }
        )
        let chapter = try (1...40).map {
            try verse($0, text: String(repeating: "x", count: 300))
        }

        await model.ask(
            verse: try verse(20, text: String(repeating: "x", count: 300)),
            chapterVerses: chapter,
            question: "Why?"
        )

        let request = try #require(recorder.requests.first)
        #expect(request.context.count == 3)
        #expect(request.context.reduce(0) { $0 + $1.text.count } <= 900)
    }

    @Test
    func displaysTheEngineErrorMessageOnFailure() async throws {
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
            provider: FailingAIProvider(error: AIEngineError.contextTooLong)
        )

        await model.ask(
            verse: verse,
            question: "Explain this verse."
        )

        #expect(
            model.state == .failed(
                AIEngineError.contextTooLong.errorDescription ?? ""
            )
        )
    }
    
    @Test
    func obtainsProviderFromFactoryForQuestion() async throws {
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
            makeProvider: {
                ImmediateAIProvider(
                    answer: "Factory answer."
                )
            }
        )

        await model.ask(
            verse: verse,
            question: "Explain this verse."
        )

        #expect(model.answer == "Factory answer.")
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

private struct FailingAIProvider: AIProvider {
    let error: any Error

    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private struct ImmediateAIProvider: AIProvider {
    let answer: String

    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BibleStudyRequest] = []

    var requests: [BibleStudyRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ request: BibleStudyRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }
}

private struct RecordingAIProvider: AIProvider {
    let recorder: RequestRecorder
    let answer: String

    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        recorder.record(request)

        return AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }
}
