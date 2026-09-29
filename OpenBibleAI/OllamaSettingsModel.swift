//
//  OllamaSettingsModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import BibleAI
import Foundation
import Observation

@MainActor
@Observable
final class OllamaSettingsModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var models: [OllamaModel] = []

    private let loadModels:
        @Sendable () async throws -> [OllamaModel]
    
    var selectedModelName: String?

    init(
        loadModels: @escaping
            @Sendable () async throws -> [OllamaModel]
    ) {
        self.loadModels = loadModels
    }

    func load() async {
        let previousState = state
        state = .loading

        do {
            let loadedModels = try await loadModels()

            models = loadedModels

            let currentSelection = selectedModelName

            if let currentSelection,
               loadedModels.contains(
                   where: { $0.name == currentSelection }
               ) {
                selectedModelName = currentSelection
            } else {
                selectedModelName = loadedModels.first?.name
            }

            state = .loaded
        } catch is CancellationError {
            state = previousState
        } catch {
            models = []
            selectedModelName = nil
            state = .failed(error.localizedDescription)
        }
    }
}
