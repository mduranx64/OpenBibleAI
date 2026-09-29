//
//  OllamaProviderTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation
import Testing
import BibleDomain

@testable import BibleAI

@Suite
struct OllamaProviderTests {
    @Test
    func streamsAssistantContentFromJSONLines() async throws {
        let client = StubHTTPLineStreamingClient(
            responseLines: [
                """
                {"message":{"role":"assistant","content":"God "},"done":false}
                """,
                """
                {"message":{"role":"assistant","content":"created."},"done":false}
                """,
                """
                {"message":{"role":"assistant","content":""},"done":true}
                """,
            ]
        )

        let provider = OllamaProvider(
            baseURL: URL(
                string: "http://localhost:11434"
            )!,
            model: "qwen3:14b",
            client: client
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

        let request = try BibleStudyRequest(
            verse: verse,
            question: "What does this teach about God?"
        )

        var receivedChunks: [String] = []

        for try await chunk in provider.streamResponse(
            for: request
        ) {
            receivedChunks.append(chunk)
        }

        #expect(receivedChunks == ["God ", "created."])

        let recordedRequest = await client.recordedRequest()

        #expect(recordedRequest?.httpMethod == "POST")
        #expect(recordedRequest?.url?.path == "/api/chat")
    }
    
    @Test
    func reportsErrorMessageFromOllamaStream() async throws {
        let client = StubHTTPLineStreamingClient(
            responseLines: [
                """
                {"error":"model 'missing-model' not found"}
                """
            ]
        )

        let provider = OllamaProvider(
            baseURL: URL(
                string: "http://localhost:11434"
            )!,
            model: "missing-model",
            client: client
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

        let request = try BibleStudyRequest(
            verse: verse,
            question: "Explain this verse."
        )

        await #expect(
            throws: OllamaProvider.ProviderError.serverMessage(
                "model 'missing-model' not found"
            )
        ) {
            for try await _ in provider.streamResponse(
                for: request
            ) {
                // No content should be produced.
            }
        }
    }
    
    @Test
    func mapsHTTPErrorBodyToServerMessage() async throws {
        let client = HTTPErrorLineStreamingClient()

        let provider = OllamaProvider(
            baseURL: URL(
                string: "http://localhost:11434"
            )!,
            model: "intentionally-missing-model",
            client: client
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

        let request = try BibleStudyRequest(
            verse: verse,
            question: "Explain this verse."
        )

        await #expect(
            throws: OllamaProvider.ProviderError.serverMessage(
                "model 'intentionally-missing-model' not found"
            )
        ) {
            for try await _ in provider.streamResponse(
                for: request
            ) {
                // No content should be produced.
            }
        }
    }
}

private actor StubHTTPLineStreamingClient:
    HTTPLineStreamingClient
{
    private let responseLines: [String]
    private var request: URLRequest?

    init(responseLines: [String]) {
        self.responseLines = responseLines
    }

    func lines(
        for request: URLRequest
    ) async throws -> AsyncThrowingStream<String, Error> {
        self.request = request
        let lines = responseLines

        return AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(line)
            }

            continuation.finish()
        }
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}

private struct HTTPErrorLineStreamingClient:
    HTTPLineStreamingClient
{
    func lines(
        for request: URLRequest
    ) async throws -> AsyncThrowingStream<String, Error> {
        throw URLSessionHTTPLineStreamingClient.ClientError
            .unacceptableStatusCode(
                404,
                body:
                    """
                    {"error":"model 'intentionally-missing-model' not found"}
                    """
            )
    }
}
