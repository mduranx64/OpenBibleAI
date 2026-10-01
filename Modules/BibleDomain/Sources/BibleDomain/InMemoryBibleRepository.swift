//
//  InMemoryBibleRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public struct InMemoryBibleRepository:
    BibleRepository,
    BibleCatalogRepository,
    BibleTextSearchRepository
{
    private let versesByReference: [BibleReference: BibleVerse]
    private let orderedBooks: [BibleBook]
    /// Verses in canonical reading order, so text search can scan once.
    private let versesInReadingOrder: [BibleVerse]

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

        // Books missing from the catalog sort after known ones, by ID.
        let bookOrder = Dictionary(
            uniqueKeysWithValues: orderedBooks.enumerated().map {
                ($1.bookID, $0)
            }
        )

        self.versesInReadingOrder = versesByReference.values.sorted {
            let lhs = $0.reference
            let rhs = $1.reference
            let lhsOrder = bookOrder[lhs.bookID] ?? Int.max
            let rhsOrder = bookOrder[rhs.bookID] ?? Int.max

            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if lhs.bookID != rhs.bookID { return lhs.bookID < rhs.bookID }
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            return lhs.verse < rhs.verse
        }
    }

    public func search(
        _ query: BibleTextQuery,
        limit: Int
    ) async throws -> BibleTextSearchResult {
        try Task.checkCancellation()

        var matches: [BibleVerse] = []
        var totalCount = 0

        for (index, verse) in versesInReadingOrder.enumerated() {
            if index.isMultiple(of: 1024) {
                try Task.checkCancellation()
            }

            guard query.matches(verse.text) else { continue }

            totalCount += 1

            if matches.count < limit {
                matches.append(verse)
            }
        }

        return BibleTextSearchResult(
            verses: matches,
            totalCount: totalCount
        )
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
