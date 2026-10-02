//
//  OpenBibleAIApp.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 13-09-26.
//

import SwiftUI
import BibleAI
import BibleDomain

@main
struct OpenBibleAIApp: App {
    @State private var appModel: AppModel
    @State private var aiEngine: AIEngineModel
    @State private var semanticSearch: SemanticSearchModel
    @State private var compare: BibleCompareModel
    private let readingPositionStore: ReadingPositionStore

    @MainActor
    init() {
        let aiEngine = AIEngineModel.live()
        let semanticSearch = SemanticSearchModel.live()

        #if DEBUG
        let library = UITestBibles.library() ?? BibleLibraryModel.live()
        #else
        let library = BibleLibraryModel.live()
        #endif

        let appModel = AppModel(
            library: library,
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
        _compare = State(initialValue: BibleCompareModel(library: library, defaults: UserDefaults.standard))
        
        _aiEngine = State(initialValue: aiEngine)
        _semanticSearch = State(initialValue: semanticSearch)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appModel: appModel,
                aiEngine: aiEngine,
                semanticSearch: semanticSearch,
                readingPositionStore: readingPositionStore,
                compare: compare
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
