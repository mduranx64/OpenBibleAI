//
//  InMemoryBibleRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

import Foundation

public struct InMemoryBibleRepository:
    BibleRepository,
    BibleCatalogRepository,
    BibleTextSearchRepository,
    BiblePassageSearchRepository
{
    private let versesByReference: [BibleReference: BibleVerse]
    private let orderedBooks: [BibleBook]
    /// Verses in canonical reading order, so text search can scan once.
    private let versesInReadingOrder: [BibleVerse]
    /// Built on first ranked search (≈ a fraction of a second), then reused.
    private let rankedIndex: LazyRankedIndex

    /// `language` (BCP-47) selects the keyword-ranking `TextAnalyzer`.
    public init(
        verses: [BibleVerse],
        books: [BibleBook] = [],
        language: String = "en"
    ) {
        self.rankedIndex = LazyRankedIndex(analyzer: TextAnalyzer(languageCode: language))
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

    /// `@concurrent` keeps the full-Bible scan off the caller's actor; plain
    /// `async` would run it on the main actor for UI callers.
    @concurrent
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

    // MARK: - Passage search

    @concurrent
    public func rankedVerses(
        matching terms: [String],
        limit: Int
    ) async throws -> [RankedVerse] {
        try Task.checkCancellation()
        let index = rankedIndex.value(building: versesInReadingOrder)
        try Task.checkCancellation()
        return index.search(terms: terms, limit: limit)
    }

    @concurrent
    public func passages(
        around references: [BibleReference],
        window: Int,
        limit: Int,
        characterBudget: Int
    ) async throws -> [BiblePassage] {
        struct Span { let bookID: String; let chapter: Int; var lower: Int; var upper: Int }

        var spans: [Span] = []
        for reference in references where versesByReference[reference] != nil {
            let lower = reference.verse - window
            let upper = reference.verse + window
            if let index = spans.firstIndex(where: {
                $0.bookID == reference.bookID && $0.chapter == reference.chapter
                    && lower <= $0.upper + 1 && upper >= $0.lower - 1
            }) {
                spans[index].lower = min(spans[index].lower, lower)
                spans[index].upper = max(spans[index].upper, upper)
            } else if spans.count < limit {
                spans.append(Span(bookID: reference.bookID, chapter: reference.chapter, lower: lower, upper: upper))
            }
        }

        var passages: [BiblePassage] = []
        var used = 0
        for span in spans {
            try Task.checkCancellation()
            let verses = (max(1, span.lower)...max(1, span.upper)).compactMap { number in
                (try? BibleReference(bookID: span.bookID, chapter: span.chapter, verse: number))
                    .flatMap { versesByReference[$0] }
            }
            let passage = BiblePassage(bookID: span.bookID, chapter: span.chapter, verses: verses)
            guard passages.isEmpty || used + passage.characterCount <= characterBudget else { break }
            used += passage.characterCount
            passages.append(passage)
        }
        return passages
    }
}

/// Thread-safe, build-once holder for the keyword index.
private final class LazyRankedIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var index: RankedVerseIndex?
    private let analyzer: TextAnalyzer

    init(analyzer: TextAnalyzer) {
        self.analyzer = analyzer
    }

    func value(building verses: [BibleVerse]) -> RankedVerseIndex {
        lock.withLock {
            if let index { return index }
            let built = RankedVerseIndex(verses: verses, analyzer: analyzer)
            index = built
            return built
        }
    }
}
