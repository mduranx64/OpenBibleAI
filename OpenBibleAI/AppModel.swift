//
//  AppModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Observation
import BibleDomain
import Foundation

/// Loads the active Bible version from the library and composes the feature
/// models for it. With no version installed, the app shows onboarding.
@MainActor
@Observable
final class AppModel {
    nonisolated struct Repositories: Sendable {
        let verses: any BibleRepository
        let catalog: any BibleCatalogRepository
        let text: any BibleTextSearchRepository
        let passages: any BiblePassageSearchRepository
    }

    /// The feature models for one loaded version.
    struct Session {
        let version: BibleVersion
        let embeddingsURL: URL?
        let catalog: BibleCatalogModel
        let referenceSearch: BibleReferenceSearchModel
        let textSearch: BibleTextSearchModel
        let chat: BibleChatModel
    }

    enum State {
        case idle
        case loading
        /// No Bible is installed: choose and download one.
        case needsVersion
        case ready(Session)
        case failed(String)
    }

    private(set) var state: State = .idle
    let library: BibleLibraryModel

    /// One chat for the app's lifetime; it answers from the reading version.
    @ObservationIgnored private lazy var chat = BibleChatModel(
        bible: { [library] id in
            guard let id = id ?? library.activeVersionID else { throw BibleLibraryModel.LibraryError.notInstalled("") }
            let loaded = try await library.bible(id)
            let catalog = loaded.repositories.catalog
            return BibleChatModel.Bible(
                version: loaded.version,
                passages: loaded.repositories.passages,
                verses: loaded.repositories.verses,
                books: { try await catalog.books() }
            )
        },
        engine: chatEngine,
        store: chatStore
    )
    @ObservationIgnored private let chatEngine: BibleChatModel.Engine
    @ObservationIgnored private let chatStore: any ChatStore
    @ObservationIgnored private var generation = 0

    init(
        library: BibleLibraryModel,
        chatEngine: BibleChatModel.Engine = .unavailable,
        chatStore: any ChatStore = InMemoryChatStore()
    ) {
        self.library = library
        self.chatEngine = chatEngine
        self.chatStore = chatStore
    }

    var session: Session? {
        if case let .ready(session) = state { return session }
        return nil
    }

    /// Opens the active version, or onboarding when none is installed.
    /// Repeated calls while loading or ready do nothing.
    func start() async {
        switch state {
        case .loading, .ready:
            return
        case .idle, .needsVersion, .failed:
            break
        }

        state = .loading
        await library.refresh()
        // Newer versions from the signed remote catalog, without blocking the reader.
        Task { await library.updateCatalog() }
        guard let id = library.activeVersionID else {
            state = .needsVersion
            return
        }
        await open(id)
    }

    /// Makes an installed version the reading version and reloads the models
    /// for it (the reader restores its saved book and chapter).
    func switchVersion(to id: String) async {
        guard id != session?.version.id, library.installedIDs.contains(id) else { return }
        library.activate(id)
        await open(id)
    }

    private func open(_ id: String) async {
        generation += 1
        let generation = generation
        do {
            let bible = try await library.bible(id)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            state = .ready(makeSession(for: bible))
        } catch is CancellationError {
            guard generation == self.generation else { return }
            state = .idle
        } catch {
            guard generation == self.generation else { return }
            state = .failed(String(describing: error))
        }
    }

    private func makeSession(for bible: LoadedBible) -> Session {
        let repositories = bible.repositories
        return Session(
            version: bible.version,
            embeddingsURL: bible.embeddingsURL,
            catalog: BibleCatalogModel(repository: repositories.catalog),
            referenceSearch: BibleReferenceSearchModel(catalog: repositories.catalog, verses: repositories.verses),
            textSearch: BibleTextSearchModel(repository: repositories.text),
            chat: chat
        )
    }
}
