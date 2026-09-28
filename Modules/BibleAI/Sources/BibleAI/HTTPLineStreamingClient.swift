//
//  HTTPLineStreamingClient.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation

protocol HTTPLineStreamingClient: Sendable {
    func lines(
        for request: URLRequest
    ) async throws -> AsyncThrowingStream<String, Error>
}
