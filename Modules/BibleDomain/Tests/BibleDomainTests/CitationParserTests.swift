//
//  CitationParserTests.swift
//  BibleDomain
//

import Testing
import BibleDomain

struct CitationParserTests {
    private func books() throws -> [BibleBook] {
        [
            try BibleBook(bookID: "MAT", name: "Matthew", canonicalOrder: 40),
            try BibleBook(bookID: "LUK", name: "Luke", canonicalOrder: 42),
            try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43),
            try BibleBook(bookID: "1JO", name: "1 John", canonicalOrder: 62)
        ]
    }

    private func ref(_ book: String, _ chapter: Int, _ verse: Int) throws -> BibleReference {
        try BibleReference(bookID: book, chapter: chapter, verse: verse)
    }

    @Test
    func findsSingleAndRangeCitationsWithTheirTextRanges() throws {
        let text = "Jesus was born in Bethlehem [Matthew 2:1], the city of David [Luke 2:4-7]."
        let citations = CitationParser.citations(in: text, books: try books())

        #expect(citations.count == 2)
        #expect(String(text[citations[0].range]) == "[Matthew 2:1]")
        #expect(citations[0].items == [.reference(try ref("MAT", 2, 1), endVerse: nil)])
        #expect(citations[1].items == [.reference(try ref("LUK", 2, 4), endVerse: 7)])
    }

    @Test
    func handlesSeveralReferencesInOneBracketAndNumberedBooks() throws {
        let citations = CitationParser.citations(in: "See [John 9:1-7; 1 John 1:5].", books: try books())

        #expect(citations.first?.items == [
            .reference(try ref("JOH", 9, 1), endVerse: 7),
            .reference(try ref("1JO", 1, 5), endVerse: nil)
        ])
    }

    @Test
    func unknownBooksAndBrokenRangesAreUnrecognizedNotDropped() throws {
        let citations = CitationParser.citations(in: "[Hezekiah 3:1] [John 9:7-2] [Luke 2]", books: try books())

        #expect(citations.map(\.items) == [
            [.unrecognized("Hezekiah 3:1")],
            [.unrecognized("John 9:7-2")],
            [.unrecognized("Luke 2")]
        ])
    }

    @Test
    func bracketsWithoutAReferenceShapeAreIgnored() throws {
        let text = "In the KJV, supplied words appear like [of] the Spirit."
        #expect(CitationParser.citations(in: text, books: try books()).isEmpty)
    }

    @Test
    func bareReferencesAreFoundOutsideBracketsLongestNameFirst() throws {
        let text = "As stated in Luke 2:4 and 1 John 4:8, see also Mark 10:46-52 and [Matthew 2:1]."
        let books = try books() + [try BibleBook(bookID: "MAR", name: "Mark", canonicalOrder: 41)]

        let citations = CitationParser.citations(in: text, books: books)

        #expect(citations.map { String(text[$0.range]) } == ["Luke 2:4", "1 John 4:8", "Mark 10:46-52", "[Matthew 2:1]"])
        #expect(citations[1].items == [.reference(try ref("1JO", 4, 8), endVerse: nil)])
        #expect(citations[2].items == [.reference(try ref("MAR", 10, 46), endVerse: 52)])
    }

    @Test
    func bareNamesWithoutChapterAndVerseOrInsideWordsAreIgnored() throws {
        let citations = CitationParser.citations(in: "John said to Luke 3 times; Johnny 3:16 is not a book.", books: try books())
        #expect(citations.isEmpty)
    }
}
