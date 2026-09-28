//
//  StudyAssistantModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

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
    private let provider: any AIProvider

    init(provider: any AIProvider) {
        self.provider = provider
    }

    func ask(
        verse: BibleVerse,
        question: String
    ) async {
        answer = ""

        do {
            let request = try BibleStudyRequest(
                verse: verse,
                question: question
            )

            state = .streaming

            for try await chunk in provider.streamResponse(
                for: request
            ) {
                try Task.checkCancellation()
                answer.append(contentsOf: chunk)
            }

            try Task.checkCancellation()
            state = .completed
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
