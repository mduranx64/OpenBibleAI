//
//  BibleStudyRequest.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation
import BibleDomain

public struct BibleStudyRequest: Hashable, Sendable {
    public let verse: BibleVerse
    public let question: String

    public init(
        verse: BibleVerse,
        question: String
    ) throws(ValidationError) {
        let trimmedQuestion = question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedQuestion.isEmpty else {
            throw .emptyQuestion
        }

        self.verse = verse
        self.question = trimmedQuestion
    }

    public enum ValidationError:
        Error,
        Equatable,
        Sendable
    {
        case emptyQuestion
    }
}
