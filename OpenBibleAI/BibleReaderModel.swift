//
//  BibleReaderModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 27-09-26.
//

import Observation
import BibleDomain

@MainActor
@Observable
final class BibleReaderModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(BibleVerse)
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored
    private let repository: any BibleRepository

    init(repository: any BibleRepository) {
        self.repository = repository
    }

    func load(reference: BibleReference) async {
        let previousState = state

        state = .loading

        do {
            let verse = try await repository.verse(
                at: reference
            )

            state = .loaded(verse)
        } catch is CancellationError {
            state = previousState
        } catch {
            state = .failed(
                String(describing: error)
            )
        }
    }
}
