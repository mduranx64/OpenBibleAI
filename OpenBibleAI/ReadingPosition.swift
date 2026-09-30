//
//  ReadingPosition.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 30-09-26.
//

import Foundation

struct ReadingPosition: Codable, Equatable, Sendable {
    let bookID: String
    let chapter: Int

    init(
        bookID: String,
        chapter: Int
    ) throws(ValidationError) {
        guard !bookID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw .blankBookID
        }

        guard chapter > 0 else {
            throw .invalidChapter(chapter)
        }

        self.bookID = bookID
        self.chapter = chapter
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let bookID = try container.decode(
            String.self,
            forKey: .bookID
        )

        let chapter = try container.decode(
            Int.self,
            forKey: .chapter
        )

        try self.init(
            bookID: bookID,
            chapter: chapter
        )
    }

    private enum CodingKeys: String, CodingKey {
        case bookID
        case chapter
    }

    enum ValidationError: Error, Equatable, Sendable {
        case blankBookID
        case invalidChapter(Int)
    }
}
