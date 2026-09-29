//
//  HTTPDataClient.swift
//  BibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation

struct HTTPDataResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol HTTPDataClient: Sendable {
    func data(
        for request: URLRequest
    ) async throws -> HTTPDataResponse
}

struct URLSessionHTTPDataClient:
    HTTPDataClient,
    Sendable
{
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(
        for request: URLRequest
    ) async throws -> HTTPDataResponse {
        let (data, response) = try await session.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        return HTTPDataResponse(
            data: data,
            statusCode: httpResponse.statusCode
        )
    }

    enum ClientError: Error, Equatable, Sendable {
        case invalidResponse
    }
}
