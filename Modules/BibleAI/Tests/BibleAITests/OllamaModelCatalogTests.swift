//
//  OllamaModelCatalogTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation
import Testing

@testable import BibleAI

@Suite
struct OllamaModelCatalogTests {
    @Test
    func loadsInstalledModels() async throws {
        let json = """
        {
            "models": [
                {
                    "name": "qwen3.8:latest",
                    "model": "qwen3.8:latest",
                    "modified_at": "2026-09-29T08:00:00Z",
                    "size": 17000000000,
                    "digest": "abc123",
                    "details": {
                        "format": "gguf",
                        "family": "qwen",
                        "families": ["qwen"],
                        "parameter_size": "27B",
                        "quantization_level": "Q4"
                    }
                }
            ]
        }
        """

        let client = StubHTTPDataClient(
            response: HTTPDataResponse(
                data: Data(json.utf8),
                statusCode: 200
            )
        )

        let catalog = OllamaModelCatalog(
            baseURL: URL(
                string: "http://localhost:11434"
            )!,
            client: client
        )

        let models = try await catalog.models()

        let model = try #require(models.first)

        #expect(models.count == 1)
        #expect(model.name == "qwen3.8:latest")
        #expect(model.size == 17_000_000_000)
        #expect(model.parameterSize == "27B")
        #expect(model.quantizationLevel == "Q4")

        let request = await client.recordedRequest()

        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.path == "/api/tags")
    }
}

private actor StubHTTPDataClient: HTTPDataClient {
    private let response: HTTPDataResponse
    private var request: URLRequest?

    init(response: HTTPDataResponse) {
        self.response = response
    }

    func data(
        for request: URLRequest
    ) async throws -> HTTPDataResponse {
        self.request = request
        return response
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}
