//
//  OllamaProvider.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation

public struct OllamaProvider: AIProvider, Sendable {
    private let requestFactory: OllamaRequestFactory
    private let client: any HTTPLineStreamingClient

    init(
        baseURL: URL,
        model: String,
        client: any HTTPLineStreamingClient
    ) {
        requestFactory = OllamaRequestFactory(
            baseURL: baseURL,
            model: model
        )

        self.client = client
    }

    public func streamResponse(
        for studyRequest: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    let request = try requestFactory.makeRequest(
                        for: studyRequest
                    )

                    let lines = try await client.lines(
                        for: request
                    )

                    let decoder = JSONDecoder()

                    for try await line in lines {
                        try Task.checkCancellation()

                        guard !line.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty else {
                            continue
                        }

                        let chunk = try decoder.decode(
                            OllamaChatChunk.self,
                            from: Data(line.utf8)
                        )

                        if !chunk.message.content.isEmpty {
                            let result = continuation.yield(
                                chunk.message.content
                            )

                            if case .terminated = result {
                                return
                            }
                        }

                        if chunk.done {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                producerTask.cancel()
            }
        }
    }
}
