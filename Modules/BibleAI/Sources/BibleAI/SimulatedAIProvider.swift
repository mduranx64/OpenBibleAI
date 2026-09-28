//
//  SimulatedAIProvider.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

public struct SimulatedAIProvider: AIProvider {
    private let chunks: [String]
    private let delay: Duration

    public init(
        chunks: [String],
        delay: Duration = .milliseconds(250)
    ) {
        self.chunks = chunks
        self.delay = delay
    }

    public func streamResponse(
        for _: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    for chunk in chunks {
                        try Task.checkCancellation()

                        if delay > .zero {
                            try await Task.sleep(for: delay)
                        }

                        let result = continuation.yield(chunk)

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
}
