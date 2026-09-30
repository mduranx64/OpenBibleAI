//
//  OpenBibleAIApp.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 13-09-26.
//

import SwiftUI
import BibleAI
import BibleData
import BibleDomain

@main
struct OpenBibleAIApp: App {
    @State private var appModel: AppModel
    @State private var studyAssistantModel: StudyAssistantModel
    @State private var ollamaSettingsModel: OllamaSettingsModel

    @MainActor
    init() {
        let appModel = AppModel(
            loadRepositories: {
                guard let fileURL = Bundle.main.url(
                    forResource: "sample-bible",
                    withExtension: "json"
                ) else {
                    throw LaunchError.missingBibleResource
                }

                let genesis = try BibleBook(
                    bookID: "GEN",
                    name: "Genesis",
                    canonicalOrder: 1
                )

                let repository = try await JSONBibleRepository.load(
                    from: fileURL,
                    books: [genesis]
                )

                return AppModel.Repositories(
                    verses: CachingBibleRepository(base: repository),
                    catalog: repository
                )
            }
        )
        
        let catalog = OllamaModelCatalog()

        let settingsModel = OllamaSettingsModel(
            loadModels: {
                try await catalog.models()
            }
        )

        let assistantModel = StudyAssistantModel(
            makeProvider: {
                guard let modelName =
                    settingsModel.selectedModelName
                else {
                    throw AIConfigurationError.noModelSelected
                }

                return OllamaProvider(
                    model: modelName
                )
            }
        )
        
        _appModel = State(initialValue: appModel)
        _studyAssistantModel = State(
            initialValue: assistantModel
        )
        
        _ollamaSettingsModel = State(
            initialValue: settingsModel
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appModel: appModel,
                studyAssistantModel: studyAssistantModel,
                ollamaSettingsModel: ollamaSettingsModel
            )
        }
        
        Settings {
            OllamaSettingsView(
                model: ollamaSettingsModel
            )
        }
    }
}

private enum LaunchError: Error, Sendable {
    case missingBibleResource
}

private enum AIConfigurationError:
    LocalizedError,
    Sendable
{
    case noModelSelected

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            "No Ollama model is selected. Open Settings and select a model."
        }
    }
}
