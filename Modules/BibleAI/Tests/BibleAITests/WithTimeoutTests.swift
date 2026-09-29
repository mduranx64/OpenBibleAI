//
//  WithTimeoutTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Testing

@testable import BibleAI

@Suite
struct WithTimeoutTests {
    @Test
    func returnsValueWhenOperationFinishesFirst() async throws {
        let result = try await withTimeout(
            after: .seconds(1)
        ) {
            "Finished"
        }

        #expect(result == "Finished")
    }

    @Test
    func throwsWhenDeadlineFinishesFirst() async {
        await #expect(
            throws: OperationTimeoutError.timedOut
        ) {
            try await withTimeout(
                after: .milliseconds(10)
            ) {
                try await Task.sleep(
                    for: .seconds(60)
                )

                return "Too late"
            }
        }
    }
}
