//
//  BibleVerseDTO.swift
//  BibleData
//
//  Created by Miguel Duran on 27-09-26.
//

import BibleDomain

struct BibleVerseDTO: Decodable, Sendable {
    let bookID: String
    let chapter: Int
    let verse: Int
    let text: String

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id"
        case chapter
        case verse
        case text
    }

    func domainModel() throws -> BibleVerse {
        let reference = try BibleReference(
            bookID: bookID,
            chapter: chapter,
            verse: verse
        )

        return try BibleVerse(
            reference: reference,
            text: text
        )
    }
}
