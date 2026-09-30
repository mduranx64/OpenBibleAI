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
    private let readingPositionStore: ReadingPositionStore

    @MainActor
    init() {
        let appModel = AppModel(
            loadRepositories: {
                guard let booksURL = Bundle.main.url(
                    forResource: "kjv-books",
                    withExtension: "json"
                ) else {
                    throw LaunchError.missingResource("kjv-books.json")
                }

                guard let versesURL = Bundle.main.url(
                    forResource: "kjv-verses",
                    withExtension: "json"
                ) else {
                    throw LaunchError.missingResource("kjv-verses.json")
                }

                let catalog = try await JSONBibleBookCatalog.load(
                    from: booksURL
                )

                let repository = try await JSONBibleRepository.load(
                    from: versesURL,
                    books: catalog.books
                )

                return AppModel.Repositories(
                    verses: CachingBibleRepository(base: repository),
                    catalog: repository
                )
            }
        )
        
        self.readingPositionStore = ReadingPositionStore(
            defaults: UserDefaults.standard
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
                ollamaSettingsModel: ollamaSettingsModel,
                readingPositionStore: readingPositionStore
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
    case missingResource(String)
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
