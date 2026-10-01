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
    /// Full book name for prompts and display; nil falls back to the book ID.
    public let bookName: String?
    /// Verses from the same chapter supplied as background, in reading order.
    public let context: [BibleVerse]
    public let question: String

    public init(
        verse: BibleVerse,
        bookName: String? = nil,
        context: [BibleVerse] = [],
        question: String
    ) throws(ValidationError) {
        let trimmedQuestion = question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedQuestion.isEmpty else {
            throw .emptyQuestion
        }

        guard context.allSatisfy({
            $0.reference.bookID == verse.reference.bookID
                && $0.reference.chapter == verse.reference.chapter
        }) else {
            throw .contextOutsideChapter
        }

        let trimmedBookName = bookName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        self.verse = verse
        self.bookName = trimmedBookName?.isEmpty == false
            ? trimmedBookName
            : nil
        self.context = context
        self.question = trimmedQuestion
    }

    public enum ValidationError:
        Error,
        Equatable,
        Sendable
    {
        case emptyQuestion
        case contextOutsideChapter
    }
}
