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
    
    @ObservationIgnored
    private var loadGeneration = 0
    
    init(repository: any BibleRepository) {
        self.repository = repository
    }

    func load(reference: BibleReference) async {
        loadGeneration += 1
        let currentGeneration = loadGeneration

        let previousState = state
        state = .loading

        do {
            let verse = try await repository.verse(at: reference)

            guard currentGeneration == loadGeneration else {
                return
            }

            state = .loaded(verse)
        } catch is CancellationError {
            guard currentGeneration == loadGeneration else {
                return
            }

            state = previousState
        } catch {
            guard currentGeneration == loadGeneration else {
                return
            }

            state = .failed(String(describing: error))
        }
    }
}
