//
//  AIProvider.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

public protocol AIProvider: Sendable {
    func streamResponse(
        for request: BibleStudyRequest
    ) -> AsyncThrowingStream<String, Error>
}
