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
