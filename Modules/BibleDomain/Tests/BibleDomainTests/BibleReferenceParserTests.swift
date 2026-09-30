import Testing
import BibleDomain

struct BibleReferenceParserTests {
    private func books() throws -> [BibleBook] {
        try [
            BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43),
            BibleBook(bookID: "1JO", name: "1 John", canonicalOrder: 62),
            BibleBook(bookID: "SOL", name: "Song of Solomon", canonicalOrder: 22),
        ]
    }

    @Test(arguments: ["John 3:16", "  jOhN   3 : 16  ", "\tJOHN\n3:\t16\n", "John 003:016"])
    func resolvesJohnWithCaseAndWhitespaceNormalization(_ input: String) throws {
        let reference = try BibleReferenceParser.parse(input, books: books())
        #expect(reference == (try BibleReference(bookID: "JOH", chapter: 3, verse: 16)))
    }

    @Test func resolvesNumberedAndMultiwordBooks() throws {
        #expect(try BibleReferenceParser.parse("1  john 2:1", books: books())
            == BibleReference(bookID: "1JO", chapter: 2, verse: 1))
        #expect(try BibleReferenceParser.parse("song of solomon 1:2", books: books())
            == BibleReference(bookID: "SOL", chapter: 1, verse: 2))
    }

    @Test func usesSuppliedCatalogIdentityRatherThanHardcodedIDs() throws {
        let catalog = try [BibleBook(bookID: "publisher-john", name: " John  ", canonicalOrder: 43)]
        let reference = try BibleReferenceParser.parse("John 3:16", books: catalog)
        #expect(reference.bookID == "publisher-john")
    }

    @Test(arguments: [
        "", " \n ", "John", "John 3", "3:16", "John3:16", "John 3:", "John :16",
        "John 3:16:17", "John 3:16-18", "John 3:16,17", "John 3:16 extra", "John 3:16; John 4:1",
        "John +3:16", "John -3:16", "John 3:-16", "John 3:+16", "John 3.0:16",
        "John ٣:١٦", "John ３:１６", "John 3：16", "John 3:1 6",
        "John 999999999999999999999999999999:16", "John 3:999999999999999999999999999999",
    ])
    func rejectsUnsupportedSyntax(_ input: String) throws {
        let catalog = try books()
        #expect(throws: BibleReferenceParser.ParseError.invalidSyntax) {
            try BibleReferenceParser.parse(input, books: catalog)
        }
    }

    @Test(arguments: ["Jn", "JOH", "Unknown", "I John", "1John"])
    func rejectsUnknownNamesAndAliases(_ name: String) throws {
        let catalog = try books()
        #expect(throws: BibleReferenceParser.ParseError.unknownBook(name)) {
            try BibleReferenceParser.parse("\(name) 3:16", books: catalog)
        }
    }

    @Test func rejectsEmptyAndAmbiguousCatalogs() throws {
        #expect(throws: BibleReferenceParser.ParseError.unknownBook("John")) {
            try BibleReferenceParser.parse("John 3:16", books: [])
        }
        var catalog = try books()
        catalog.append(try BibleBook(bookID: "OTHER", name: " JOHN ", canonicalOrder: 44))
        #expect(throws: BibleReferenceParser.ParseError.ambiguousBook("John")) {
            try BibleReferenceParser.parse("John 3:16", books: catalog)
        }
    }

    @Test func reusesDomainPositionValidation() throws {
        let catalog = try books()
        #expect(throws: BibleReference.ValidationError.invalidChapter(0)) {
            try BibleReferenceParser.parse("John 0:16", books: catalog)
        }
        #expect(throws: BibleReference.ValidationError.invalidVerse(0)) {
            try BibleReferenceParser.parse("John 3:0", books: catalog)
        }
    }

    @Test func doesNotClaimVerseAvailability() throws {
        let reference = try BibleReferenceParser.parse("John 999:999", books: books())
        #expect(reference == (try BibleReference(bookID: "JOH", chapter: 999, verse: 999)))
    }
}
