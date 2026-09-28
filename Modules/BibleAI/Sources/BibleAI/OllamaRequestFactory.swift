//
//  OllamaRequestFactory.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation

struct OllamaRequestFactory: Sendable {
    let baseURL: URL
    let model: String

    func makeRequest(
        for studyRequest: BibleStudyRequest
    ) throws -> URLRequest {
        let reference = studyRequest.verse.reference

        let systemPrompt = """
        You are a careful Bible study assistant.
        Base your answer on the supplied biblical passage.
        Clearly distinguish the text from interpretation.
        Do not invent Scripture citations.
        """

        let userPrompt = """
        Passage: \(reference.bookID) \
        \(reference.chapter):\(reference.verse)

        Text:
        \(studyRequest.verse.text)

        Question:
        \(studyRequest.question)
        """

        let body = ChatRequest(
            model: model,
            messages: [
                Message(
                    role: "system",
                    content: systemPrompt
                ),
                Message(
                    role: "user",
                    content: userPrompt
                ),
            ],
            stream: true,
            think: false
        )

        let endpoint = baseURL.appending(
            path: "api/chat"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = try JSONEncoder().encode(body)

        return request
    }
}

private struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let think: Bool
}

private struct Message: Encodable, Sendable {
    let role: String
    let content: String
}
