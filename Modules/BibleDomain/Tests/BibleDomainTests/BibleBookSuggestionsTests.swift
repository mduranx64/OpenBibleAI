import Testing
import BibleDomain

struct BibleBookSuggestionsTests {
    private func books() throws -> [BibleBook] {
        try [
            BibleBook(bookID: "GEN", name: "Génesis", canonicalOrder: 1),
            BibleBook(bookID: "JOS", name: "Joshua", canonicalOrder: 6),
            BibleBook(bookID: "1SA", name: "1 Samuel", canonicalOrder: 9),
            BibleBook(bookID: "JOB", name: "Job", canonicalOrder: 18),
            BibleBook(bookID: "SOL", name: "Song of Solomon", canonicalOrder: 22),
            BibleBook(bookID: "JOE", name: "Joel", canonicalOrder: 29),
            BibleBook(bookID: "JON", name: "Jonah", canonicalOrder: 32),
            BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43),
            BibleBook(bookID: "1JO", name: "1 John", canonicalOrder: 62),
            BibleBook(bookID: "2JO", name: "2 John", canonicalOrder: 63),
            BibleBook(bookID: "3JO", name: "3 John", canonicalOrder: 64),
        ]
    }

    private func ids(_ input: String, limit: Int = 8) throws -> [String] {
        BibleBookSuggestions.matching(input, in: try books(), limit: limit).map(\.bookID)
    }

    @Test func namesStartingWithTheInputComeBeforeNumberedBooksInCanonicalOrder() throws {
        #expect(try ids("jo") == ["JOS", "JOB", "JOE", "JON", "JOH", "1JO", "2JO", "3JO"])
    }

    @Test func numberedPrefixNarrowsToThatBook() throws {
        #expect(try ids("1 jo") == ["1JO"])
        #expect(try ids("1") == ["1SA", "1JO"])
    }

    @Test(arguments: ["GEN", "genes", "  gén"])
    func ignoresCaseDiacriticsAndLeadingWhitespace(_ input: String) throws {
        #expect(try ids(input) == ["GEN"])
    }

    @Test func multiwordNamesMatchWithCollapsedWhitespace() throws {
        #expect(try ids("song ") == ["SOL"])
        #expect(try ids("song  of") == ["SOL"])
    }

    @Test(arguments: ["", "   ", "John", "john ", "1 John", "GENESIS", "John 3", "John 3:16", "Revelation", "love"])
    func completeNamesChaptersAndUnknownTextSuggestNothing(_ input: String) throws {
        #expect(try ids(input).isEmpty)
    }

    @Test func limitCapsTheSuggestions() throws {
        #expect(try ids("jo", limit: 3) == ["JOS", "JOB", "JOE"])
    }

    @Test func followsCatalogOrderRatherThanArrayOrder() throws {
        let shuffled = try books().reversed()
        let result = BibleBookSuggestions.matching("jo", in: Array(shuffled)).map(\.bookID)
        #expect(result == ["JOS", "JOB", "JOE", "JON", "JOH", "1JO", "2JO", "3JO"])
    }
}
