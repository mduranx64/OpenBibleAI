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
    private let startupTimeout: Duration

    init(
        baseURL: URL,
        model: String,
        client: any HTTPLineStreamingClient,
        startupTimeout: Duration = .seconds(120)
    ) {
        requestFactory = OllamaRequestFactory(
            baseURL: baseURL,
            model: model
        )

        self.client = client
        self.startupTimeout = startupTimeout
    }
    
    public init(
        baseURL: URL = URL(
            string: "http://localhost:11434"
        )!,
        model: String,
        startupTimeout: Duration = .seconds(120)
    ) {
        requestFactory = OllamaRequestFactory(
            baseURL: baseURL,
            model: model
        )

        client = URLSessionHTTPLineStreamingClient()
        self.startupTimeout = startupTimeout
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

                    let client = self.client

                    let lines = try await withTimeout(
                        after: startupTimeout
                    ) {
                        try await client.lines(for: request)
                    }

                    let decoder = JSONDecoder()

                    for try await line in lines {
                        try Task.checkCancellation()

                        guard !line.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty else {
                            continue
                        }

                        let data = Data(line.utf8)

                        if let errorResponse = try? decoder.decode(
                            OllamaErrorResponse.self,
                            from: data
                        ) {
                            throw ProviderError.serverMessage(
                                errorResponse.error
                            )
                        }

                        let chunk = try decoder.decode(
                            OllamaChatChunk.self,
                            from: data
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
                    continuation.finish(throwing: Self.mappedError(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                producerTask.cancel()
            }
        }
    }
    
    public enum ProviderError:
        LocalizedError,
        Equatable,
        Sendable
    {
        case serverUnavailable
        case serverMessage(String)
        case requestTimedOut

        public var errorDescription: String? {
            switch self {
            case .serverUnavailable:
                """
                Cannot connect to Ollama. \
                Make sure Ollama is installed and running.
                """
            case .requestTimedOut:
                """
                Ollama did not respond in time. \
                The selected model may still be loading.
                """
            case let .serverMessage(message):
                message
            }
        }
    }
    
    private static func mappedError(
        _ error: any Error
    ) -> any Error {
        if error is OperationTimeoutError {
            return ProviderError.requestTimedOut
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost,
                 .cannotFindHost,
                 .networkConnectionLost:
                return ProviderError.serverUnavailable

            default:
                return urlError
            }
        }

        guard
            let clientError =
                error as? URLSessionHTTPLineStreamingClient.ClientError
        else {
            return error
        }

        guard case let .unacceptableStatusCode(
            _,
            body
        ) = clientError,
        let body,
        let response = try? JSONDecoder().decode(
            OllamaErrorResponse.self,
            from: Data(body.utf8)
        ) else {
            return clientError
        }

        return ProviderError.serverMessage(
            response.error
        )
    }
}

private struct OllamaErrorResponse:
    Decodable,
    Sendable
{
    let error: String
}
