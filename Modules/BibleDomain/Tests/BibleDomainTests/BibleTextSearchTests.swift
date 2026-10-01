//
//  BibleTextSearchTests.swift
//  BibleDomain
//

import Testing
import BibleDomain

struct BibleTextQueryTests {
    @Test(arguments: ["", " ", "a", "  a  ", "\"\"", "\" \""])
    func tooShortOrEmptyQueriesAreRejected(raw: String) {
        #expect(throws: BibleTextQuery.ParseError.tooShort) {
            try BibleTextQuery(raw)
        }
    }

    @Test
    func unquotedWordsBecomeIndependentTerms() throws {
        let query = try BibleTextQuery("Love  one\tAnother")

        #expect(query.terms == [["love"], ["one"], ["another"]])
    }

    @Test
    func quotedTextBecomesOnePhraseTerm() throws {
        let query = try BibleTextQuery("grace \"In the Beginning\"")

        #expect(query.terms == [["grace"], ["in", "the", "beginning"]])
    }

    @Test
    func unterminatedQuoteTreatsRemainderAsPhrase() throws {
        let query = try BibleTextQuery("\"in the beg")

        #expect(query.terms == [["in", "the", "beg"]])
    }

    @Test
    func punctuationAndDiacriticsAreNormalized() throws {
        let query = try BibleTextQuery("LORD, Élan!")

        #expect(query.terms == [["lord"], ["elan"]])
    }
}

struct BibleTextSearchTests {
    private func verse(
        _ book: String,
        _ chapter: Int,
        _ number: Int,
        _ text: String
    ) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(
                bookID: book,
                chapter: chapter,
                verse: number
            ),
            text: text
        )
    }

    private func books() throws -> [BibleBook] {
        [
            try BibleBook(bookID: "PSA", name: "Psalms", canonicalOrder: 19),
            try BibleBook(bookID: "GEN", name: "Genesis", canonicalOrder: 1),
            try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)
        ]
    }

    private func repository() throws -> InMemoryBibleRepository {
        InMemoryBibleRepository(
            verses: [
                try verse("JOH", 13, 34, "That ye love one another; as I have loved you."),
                try verse("PSA", 23, 1, "The LORD is my shepherd; I shall not want."),
                try verse("GEN", 1, 1, "In the beginning God created the heaven and the earth."),
                try verse("GEN", 1, 2, "And the earth was without form, and void."),
                try verse("PSA", 119, 97, "O how love I thy law! it is my meditation."),
                try verse("JOH", 3, 16, "For God so loved the world, that he gave his only begotten Son."),
                try verse("JOH", 1, 1, "In the beginning was the Word, and the Word was with God.")
            ],
            books: try books()
        )
    }

    private func search(
        _ raw: String,
        limit: Int = 100
    ) async throws -> BibleTextSearchResult {
        try await repository().search(
            BibleTextQuery(raw),
            limit: limit
        )
    }

    private func references(
        _ result: BibleTextSearchResult
    ) -> [String] {
        result.verses.map {
            "\($0.reference.bookID) \($0.reference.chapter):\($0.reference.verse)"
        }
    }

    @Test
    func matchingIgnoresCase() async throws {
        let result = try await search("lord")

        #expect(references(result) == ["PSA 23:1"])
    }

    @Test
    func matchesWholeWordsNotSubstrings() async throws {
        let result = try await search("love")

        #expect(references(result) == ["PSA 119:97", "JOH 13:34"])
    }

    @Test
    func allWordsMustAppearInAnyOrder() async throws {
        let result = try await search("earth beginning")

        #expect(references(result) == ["GEN 1:1"])

        let reordered = try await search("another love")

        #expect(references(reordered) == ["JOH 13:34"])
    }

    @Test
    func quotedPhraseRequiresConsecutiveWords() async throws {
        let phrase = try await search("\"in the beginning\"")

        #expect(references(phrase) == ["GEN 1:1", "JOH 1:1"])

        let notConsecutive = try await search("\"beginning the in\"")

        #expect(notConsecutive.verses.isEmpty)
    }

    @Test
    func resultsFollowCanonicalOrderNotInsertionOrder() async throws {
        let result = try await search("the")

        #expect(
            references(result) == [
                "GEN 1:1", "GEN 1:2", "PSA 23:1", "JOH 1:1", "JOH 3:16"
            ]
        )
    }

    @Test
    func noMatchReturnsEmptyResult() async throws {
        let result = try await search("zebra")

        #expect(result.verses.isEmpty)
        #expect(result.totalCount == 0)
        #expect(result.isTruncated == false)
    }

    @Test
    func limitTruncatesButReportsTotalCount() async throws {
        let result = try await search("the", limit: 2)

        #expect(references(result) == ["GEN 1:1", "GEN 1:2"])
        #expect(result.totalCount == 5)
        #expect(result.isTruncated)
    }

    @Test
    func resultAtExactLimitIsNotTruncated() async throws {
        let result = try await search("the", limit: 5)

        #expect(result.verses.count == 5)
        #expect(result.isTruncated == false)
    }

    @Test
    func cancelledSearchThrowsCancellation() async throws {
        let repository = try repository()
        let query = try BibleTextQuery("the")

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.search(query, limit: 10)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
