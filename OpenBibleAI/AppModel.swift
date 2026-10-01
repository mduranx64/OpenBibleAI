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
    }

    enum State {
        case idle
        case loading
        case ready(
            BibleReaderModel,
            BibleCatalogModel,
            BibleReferenceSearchModel,
            BibleTextSearchModel
        )
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored
    private let loadRepositories:
        @MainActor @Sendable () async throws -> Repositories

    init(
        loadRepositories: @escaping @MainActor @Sendable
        () async throws -> Repositories
    ) {
        self.loadRepositories = loadRepositories
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

            state = .ready(
                readerModel,
                catalogModel,
                searchModel,
                textSearchModel
            )
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
