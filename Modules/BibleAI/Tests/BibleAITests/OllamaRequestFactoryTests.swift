//
//  OllamaRequestFactoryTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation
import Testing
import BibleDomain

@testable import BibleAI

@Suite
struct OllamaRequestFactoryTests {
    @Test
    func buildsStreamingChatRequest() throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning, God created the heavens and the earth."
        )

        let studyRequest = try BibleStudyRequest(
            verse: verse,
            question: "What does this teach about God?"
        )

        let factory = OllamaRequestFactory(
            baseURL: URL(
                string: "http://localhost:11434"
            )!,
            model: "qwen3:14b"
        )

        let request = try factory.makeRequest(
            for: studyRequest
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/chat")

        #expect(
            request.value(
                forHTTPHeaderField: "Content-Type"
            ) == "application/json"
        )

        let bodyData = try #require(request.httpBody)

        let body = try JSONDecoder().decode(
            EncodedChatRequest.self,
            from: bodyData
        )

        #expect(body.model == "qwen3:14b")
        #expect(body.stream)
        #expect(body.think == false)
        #expect(body.messages.count == 2)

        #expect(body.messages[0].role == "system")
        #expect(body.messages[1].role == "user")

        #expect(
            body.messages[1].content.contains("GEN 1:1")
        )

        #expect(
            body.messages[1].content.contains(verse.text)
        )

        #expect(
            body.messages[1].content.contains(
                studyRequest.question
            )
        )
    }

    private func makeBody(
        _ studyRequest: BibleStudyRequest
    ) throws -> EncodedChatRequest {
        let factory = OllamaRequestFactory(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "qwen3:14b"
        )
        let request = try factory.makeRequest(for: studyRequest)
        return try JSONDecoder().decode(
            EncodedChatRequest.self,
            from: try #require(request.httpBody)
        )
    }

    private func verse(_ number: Int) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(bookID: "JOH", chapter: 3, verse: number),
            text: "Text of verse \(number)."
        )
    }

    @Test
    func promptUsesFullBookNameAndMarksTheSelectedVerseWithinContext() throws {
        let studyRequest = try BibleStudyRequest(
            verse: verse(16),
            bookName: "John",
            context: [verse(15), verse(16), verse(17)],
            question: "What is the main idea?"
        )

        let prompt = try makeBody(studyRequest).messages[1].content

        #expect(prompt.contains("Passage: John 3:16"))
        #expect(!prompt.contains("JOH"))
        #expect(prompt.contains("Selected verse:"))
        #expect(prompt.contains("Chapter context"))
        #expect(prompt.contains("[15] Text of verse 15."))
        #expect(prompt.contains("> [16] Text of verse 16."))
        #expect(prompt.contains("[17] Text of verse 17."))
        #expect(prompt.contains("What is the main idea?"))
    }

    @Test
    func promptWithoutContextOmitsTheContextSection() throws {
        let studyRequest = try BibleStudyRequest(
            verse: verse(16),
            question: "What is the main idea?"
        )

        let prompt = try makeBody(studyRequest).messages[1].content

        #expect(prompt.contains("Passage: JOH 3:16"))
        #expect(!prompt.contains("Chapter context"))
    }

    @Test
    func systemPromptSeparatesScriptureFromInterpretationAndForbidsInventedCitations() throws {
        let studyRequest = try BibleStudyRequest(
            verse: verse(16),
            context: [verse(16)],
            question: "Why?"
        )

        let system = try makeBody(studyRequest).messages[0].content

        #expect(system.contains("Do not invent Scripture citations"))
        #expect(system.contains("context"))
        #expect(system.lowercased().contains("interpretation"))
    }
}

private struct EncodedChatRequest: Decodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let think: Bool

    struct Message: Decodable {
        let role: String
        let content: String
    }
}
