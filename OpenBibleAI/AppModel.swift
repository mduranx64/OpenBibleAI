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
    enum State {
        case idle
        case loading
        case ready(BibleReaderModel)
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored
    private let loadRepository:
        @MainActor @Sendable () async throws -> any BibleRepository

    init(
        loadRepository: @escaping @MainActor @Sendable
        () async throws -> any BibleRepository
    ) {
        self.loadRepository = loadRepository
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
            let repository = try await loadRepository()

            try Task.checkCancellation()

            let readerModel = BibleReaderModel(
                repository: repository
            )

            state = .ready(readerModel)
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(
                String(describing: error)
            )
        }
    }
}
