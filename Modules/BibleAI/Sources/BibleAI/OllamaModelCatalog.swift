//
//  OllamaModelCatalog.swift
//  BibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation

public struct OllamaModelCatalog: Sendable {
    private let baseURL: URL
    private let client: any HTTPDataClient

    public init(
        baseURL: URL = URL(
            string: "http://localhost:11434"
        )!
    ) {
        self.baseURL = baseURL
        client = URLSessionHTTPDataClient()
    }

    init(
        baseURL: URL,
        client: any HTTPDataClient
    ) {
        self.baseURL = baseURL
        self.client = client
    }

    public func models() async throws -> [OllamaModel] {
        let endpoint = baseURL.appending(
            path: "api/tags"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        let response = try await client.data(for: request)

        guard 200..<300 ~= response.statusCode else {
            if let errorResponse = try? JSONDecoder().decode(
                ErrorResponse.self,
                from: response.data
            ) {
                throw OllamaProvider.ProviderError.serverMessage(
                    errorResponse.error
                )
            }

            throw CatalogError.unacceptableStatusCode(
                response.statusCode
            )
        }

        let decodedResponse = try JSONDecoder().decode(
            ModelsResponse.self,
            from: response.data
        )

        return decodedResponse.models
            .map {
                OllamaModel(
                    name: $0.name,
                    size: $0.size,
                    parameterSize: $0.details?.parameterSize,
                    quantizationLevel:
                        $0.details?.quantizationLevel
                )
            }
            .sorted {
                $0.name < $1.name
            }
    }

    enum CatalogError: Error, Equatable, Sendable {
        case unacceptableStatusCode(Int)
    }
}

private struct ModelsResponse: Decodable {
    let models: [Model]
}

private struct Model: Decodable {
    let name: String
    let size: Int64
    let details: Details?
}

private struct Details: Decodable {
    let parameterSize: String?
    let quantizationLevel: String?

    private enum CodingKeys: String, CodingKey {
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}
