//
//  InMemoryBibleRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public struct InMemoryBibleRepository:
    BibleRepository,
    BibleCatalogRepository
{
    private let versesByReference: [BibleReference: BibleVerse]
    private let orderedBooks: [BibleBook]

    public init(
        verses: [BibleVerse],
        books: [BibleBook] = []
    ) {
        var versesByReference: [BibleReference: BibleVerse] = [:]

        for verse in verses {
            versesByReference[verse.reference] = verse
        }

        self.versesByReference = versesByReference
        self.orderedBooks = books.sorted {
            $0.canonicalOrder < $1.canonicalOrder
        }
    }

    public func books() async throws -> [BibleBook] {
        orderedBooks
    }

    public func verse(
        at reference: BibleReference
    ) async throws(LookupError) -> BibleVerse {
        guard let verse = versesByReference[reference] else {
            throw .verseNotFound(reference)
        }

        return verse
    }
    
    public func chapters(in bookID: String) async throws -> [Int] {
        let chapterNumbers = versesByReference.keys
            .filter { $0.bookID == bookID }
            .map { $0.chapter }

        return Set(chapterNumbers).sorted()
    }
    
    public func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        versesByReference.values
            .filter {
                $0.reference.bookID == bookID
                    && $0.reference.chapter == chapter
            }
            .sorted {
                $0.reference.verse < $1.reference.verse
            }
    }

    public enum LookupError: Error, Equatable, Sendable {
        case verseNotFound(BibleReference)
    }
}
