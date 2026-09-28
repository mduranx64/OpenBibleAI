//
//  AIResponseCollector.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

public struct AIResponseCollector: Sendable {
    private let provider: any AIProvider

    public init(provider: any AIProvider) {
        self.provider = provider
    }

    public func response(
        for request: BibleStudyRequest
    ) async throws -> String {
        var chunks: [String] = []

        for try await chunk in provider.streamResponse(
            for: request
        ) {
            try Task.checkCancellation()
            chunks.append(chunk)
        }

        try Task.checkCancellation()

        return chunks.joined()
    }
}
