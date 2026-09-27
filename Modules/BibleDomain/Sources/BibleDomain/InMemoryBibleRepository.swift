//
//  InMemoryBibleRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public struct InMemoryBibleRepository: BibleRepository {
    private let versesByReference: [BibleReference: BibleVerse]

    public init(verses: [BibleVerse]) {
        var versesByReference: [BibleReference: BibleVerse] = [:]

        for verse in verses {
            versesByReference[verse.reference] = verse
        }

        self.versesByReference = versesByReference
    }

    public func verse(
        at reference: BibleReference
    ) async throws(LookupError) -> BibleVerse {
        guard let verse = versesByReference[reference] else {
            throw .verseNotFound(reference)
        }

        return verse
    }

    public enum LookupError: Error, Equatable, Sendable {
        case verseNotFound(BibleReference)
    }
}
