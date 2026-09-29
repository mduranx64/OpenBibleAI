//
//  OllamaSettingsModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation
import BibleAI
import Testing

@testable import OpenBibleAI

@MainActor
@Suite
struct OllamaSettingsModelTests {
    @Test
    func loadsAvailableModels() async {
        let expectedModels = [
            OllamaModel(
                name: "qwen3.8:latest",
                size: 17_000_000_000,
                parameterSize: "30B",
                quantizationLevel: "Q4_K_M"
            )
        ]

        let model = OllamaSettingsModel(
            loadModels: {
                expectedModels
            }
        )

        await model.load()

        #expect(model.models == expectedModels)
    }
    
    @Test
    func reportsFailureWhenLoadingModelsFails() async {
        let model = OllamaSettingsModel(
            loadModels: {
                throw TestError.catalogUnavailable
            }
        )

        await model.load()

        #expect(
            model.state == .failed(
                "The Ollama model catalog is unavailable."
            )
        )
        #expect(model.models.isEmpty)
    }
    
    @Test
    func selectsFirstAvailableModelAfterLoading() async {
        let firstModel = OllamaModel(
            name: "qwen3.8:latest",
            size: 17_000_000_000,
            parameterSize: "30B",
            quantizationLevel: "Q4_K_M"
        )

        let secondModel = OllamaModel(
            name: "gemma3:latest",
            size: 8_000_000_000,
            parameterSize: "12B",
            quantizationLevel: "Q4_K_M"
        )

        let model = OllamaSettingsModel(
            loadModels: {
                [firstModel, secondModel]
            }
        )

        await model.load()

        #expect(model.selectedModelName == firstModel.name)
        #expect(model.state == .loaded)
    }
    
    @Test
    func preservesSelectedModelWhenReloading() async {
        let firstModel = OllamaModel(
            name: "gemma3:latest",
            size: 8_000_000_000,
            parameterSize: "12B",
            quantizationLevel: "Q4_K_M"
        )

        let secondModel = OllamaModel(
            name: "qwen3.8:latest",
            size: 17_000_000_000,
            parameterSize: "30B",
            quantizationLevel: "Q4_K_M"
        )

        let model = OllamaSettingsModel(
            loadModels: {
                [firstModel, secondModel]
            }
        )

        await model.load()
        model.selectedModelName = secondModel.name

        await model.load()

        #expect(model.selectedModelName == secondModel.name)
    }
    
    @Test
    func cancellationRestoresIdleState() async {
        let model = OllamaSettingsModel(
            loadModels: {
                try await Task.sleep(for: .seconds(60))
                return []
            }
        )

        let task = Task {
            await model.load()
        }

        await Task.yield()
        task.cancel()
        await task.value

        #expect(model.state == .idle)
    }
}

private enum TestError: LocalizedError {
    case catalogUnavailable

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            "The Ollama model catalog is unavailable."
        }
    }
}
