//
//  WithTimeout.swift
//  BibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

public enum OperationTimeoutError:
    Error,
    Equatable,
    Sendable
{
    case timedOut
}

func withTimeout<Value: Sendable>(
    after duration: Duration,
    operation:
        @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(
        of: Value.self
    ) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: duration)
            try Task.checkCancellation()

            throw OperationTimeoutError.timedOut
        }

        defer {
            group.cancelAll()
        }

        guard let result = try await group.next() else {
            throw CancellationError()
        }

        return result
    }
}
