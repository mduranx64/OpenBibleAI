//
//  StudyAssistantModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation
import Observation
import BibleAI
import BibleDomain

@MainActor
@Observable
final class StudyAssistantModel {
    enum State: Equatable {
        case idle
        case streaming
        case completed
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var answer = ""

    @ObservationIgnored
    private let makeProvider:
        @MainActor @Sendable () throws -> any AIProvider
    
    @ObservationIgnored
    private var requestGeneration = 0

    init(provider: any AIProvider) {
        self.makeProvider = {
            provider
        }
    }
    
    init(
        makeProvider: @escaping
            @MainActor @Sendable () throws -> any AIProvider
    ) {
        self.makeProvider = makeProvider
    }

    func ask(
        verse: BibleVerse,
        question: String
    ) async {
        requestGeneration += 1
        let currentGeneration = requestGeneration

        answer = ""

        do {
            let request = try BibleStudyRequest(
                verse: verse,
                question: question
            )

            let provider = try makeProvider()

            state = .streaming
 
            for try await chunk in provider.streamResponse(
                for: request
            ) {
                try Task.checkCancellation()

                guard currentGeneration == requestGeneration else {
                    return
                }

                answer.append(contentsOf: chunk)
            }

            try Task.checkCancellation()

            guard currentGeneration == requestGeneration else {
                return
            }

            state = .completed
        } catch is CancellationError {
            guard currentGeneration == requestGeneration else {
                return
            }

            state = .idle
        } catch {
            guard currentGeneration == requestGeneration else {
                return
            }

            state = .failed(Self.message(for: error))
        }
    }
    
    private static func message(
        for error: any Error
    ) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}


