//
//  AppModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Observation
import BibleDomain

@MainActor
@Observable
final class AppModel {
    struct Repositories: Sendable {
        let verses: any BibleRepository
        let catalog: any BibleCatalogRepository
        let text: any BibleTextSearchRepository
        let passages: any BiblePassageSearchRepository
    }

    enum State {
        case idle
        case loading
        case ready(
            BibleReaderModel,
            BibleCatalogModel,
            BibleReferenceSearchModel,
            BibleTextSearchModel,
            BibleChatModel
        )
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored
    private let loadRepositories:
        @MainActor @Sendable () async throws -> Repositories

    @ObservationIgnored
    private let chatEngine: BibleChatModel.Engine

    @ObservationIgnored
    private let chatStore: any ChatStore

    init(
        loadRepositories: @escaping @MainActor @Sendable
        () async throws -> Repositories,
        chatEngine: BibleChatModel.Engine = .unavailable,
        chatStore: any ChatStore = InMemoryChatStore()
    ) {
        self.loadRepositories = loadRepositories
        self.chatEngine = chatEngine
        self.chatStore = chatStore
    }

    func start() async {
        switch state {
        case .loading, .ready:
            return

        case .idle, .failed:
            break
        }

        state = .loading

        do {
            let repositories = try await loadRepositories()

            try Task.checkCancellation()

            let readerModel = BibleReaderModel(
                repository: repositories.verses
            )

            let catalogModel = BibleCatalogModel(
                repository: repositories.catalog
            )

            let searchModel = BibleReferenceSearchModel(
                catalog: repositories.catalog,
                verses: repositories.verses
            )

            let textSearchModel = BibleTextSearchModel(
                repository: repositories.text
            )

            let catalog = repositories.catalog
            let chatModel = BibleChatModel(
                passages: repositories.passages,
                verses: repositories.verses,
                books: { try await catalog.books() },
                engine: chatEngine,
                store: chatStore
            )

            state = .ready(
                readerModel,
                catalogModel,
                searchModel,
                textSearchModel,
                chatModel
            )
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
