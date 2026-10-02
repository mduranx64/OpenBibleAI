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
    @State private var aiEngine: AIEngineModel
    @State private var semanticSearch: SemanticSearchModel
    private let readingPositionStore: ReadingPositionStore

    @MainActor
    init() {
        let aiEngine = AIEngineModel.live()
        let semanticSearch = SemanticSearchModel.live()

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
                    catalog: repository,
                    text: repository,
                    passages: repository
                )
            },
            chatEngine: BibleChatModel.Engine(
                makeStreamer: { try aiEngine.makePromptStreamer() },
                passageBudget: { aiEngine.contextCharacterLimit },
                semanticSearch: { semanticSearch.searcher() }
            ),
            chatStore: FileChatStore.live()
        )
        
        self.readingPositionStore = ReadingPositionStore(
            defaults: UserDefaults.standard
        )
        
        _appModel = State(initialValue: appModel)
        
        _aiEngine = State(initialValue: aiEngine)
        _semanticSearch = State(initialValue: semanticSearch)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appModel: appModel,
                aiEngine: aiEngine,
                semanticSearch: semanticSearch,
                readingPositionStore: readingPositionStore
            )
        }
        // Used when there is no saved window frame (first launch).
        .defaultSize(width: 1280, height: 800)

        #if os(macOS)
        Settings {
            AISettingsView(engine: aiEngine, semanticSearch: semanticSearch)
        }
        #endif
    }
}

private enum LaunchError: Error, Sendable {
    case missingResource(String)
}
