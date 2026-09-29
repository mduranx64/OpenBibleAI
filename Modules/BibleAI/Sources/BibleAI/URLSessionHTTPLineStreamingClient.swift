//
//  URLSessionHTTPLineStreamingClient.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation

struct URLSessionHTTPLineStreamingClient:
    HTTPLineStreamingClient,
    Sendable
{
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lines(
        for request: URLRequest
    ) async throws -> AsyncThrowingStream<String, Error> {
        let (bytes, response) = try await session.bytes(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let maximumErrorBodySize = 64 * 1_024
            var errorData = Data()

            for try await byte in bytes {
                guard errorData.count < maximumErrorBodySize else {
                    break
                }

                errorData.append(byte)
            }

            let body: String?

            if errorData.isEmpty {
                body = nil
            } else {
                body = String(
                    data: errorData,
                    encoding: .utf8
                )
            }

            throw ClientError.unacceptableStatusCode(
                httpResponse.statusCode,
                body: body
            )
        }

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        let result = continuation.yield(line)

                        if case .terminated = result {
                            return
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

    enum ClientError: Error, Equatable, Sendable {
        case invalidResponse

        case unacceptableStatusCode(
            Int,
            body: String?
        )
    }
}
