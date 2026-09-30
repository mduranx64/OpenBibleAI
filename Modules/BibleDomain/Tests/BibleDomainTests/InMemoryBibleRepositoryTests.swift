//
//  InMemoryBibleRepositoryTests.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

import Testing
import BibleDomain

struct InMemoryBibleRepositoryTests {
    @Test
    func repositoryReturnsStoredVerse() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let expectedVerse = try BibleVerse(
            reference: reference,
            text: "In the beginning God created the heavens and the earth."
        )

        let repository = InMemoryBibleRepository(
            verses: [expectedVerse]
        )

        let returnedVerse = try await repository.verse(
            at: reference
        )

        #expect(returnedVerse == expectedVerse)
    }
    
    @Test
    func repositoryThrowsWhenVerseIsMissing() async throws {
        let missingReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 2
        )

        let repository = InMemoryBibleRepository(verses: [])

        await #expect(
            throws: InMemoryBibleRepository.LookupError
                .verseNotFound(missingReference)
        ) {
            try await repository.verse(at: missingReference)
        }
    }
    
    @Test
    func repositoryReturnsBooksInCanonicalOrder() async throws {
        let genesis = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        let exodus = try BibleBook(
            bookID: "EXO",
            name: "Exodus",
            canonicalOrder: 2
        )

        let repository = InMemoryBibleRepository(
            verses: [],
            books: [exodus, genesis]
        )

        let catalog: any BibleCatalogRepository = repository
        let returnedBooks = try await catalog.books()

        #expect(returnedBooks == [genesis, exodus])
    }
    
    @Test
    func repositoryReturnsEmptyCatalogWhenNoBooksAreProvided() async throws {
        let repository = InMemoryBibleRepository(verses: [])

        let catalog: any BibleCatalogRepository = repository
        let returnedBooks = try await catalog.books()

        #expect(returnedBooks.isEmpty)
    }
    
    @Test
    func repositoryReturnsUniqueChaptersInAscendingOrder() async throws {
        let references = [
            try BibleReference(bookID: "GEN", chapter: 2, verse: 1),
            try BibleReference(bookID: "GEN", chapter: 1, verse: 1),
            try BibleReference(bookID: "GEN", chapter: 2, verse: 2)
        ]

        let verses = try references.map { reference in
            try BibleVerse(
                reference: reference,
                text: "Sample verse."
            )
        }

        let repository = InMemoryBibleRepository(verses: verses)
        let catalog: any BibleCatalogRepository = repository

        let chapters = try await catalog.chapters(in: "GEN")

        #expect(chapters == [1, 2])
    }
    
    @Test
    func repositoryReturnsChaptersOnlyForRequestedBook() async throws {
        let references = [
            try BibleReference(bookID: "GEN", chapter: 1, verse: 1),
            try BibleReference(bookID: "EXO", chapter: 3, verse: 1)
        ]

        let verses = try references.map { reference in
            try BibleVerse(
                reference: reference,
                text: "Sample verse."
            )
        }

        let repository = InMemoryBibleRepository(verses: verses)
        let catalog: any BibleCatalogRepository = repository

        let chapters = try await catalog.chapters(in: "GEN")

        #expect(chapters == [1])
    }
    
    @Test
    func repositoryReturnsNoChaptersForBookWithoutStoredVerses() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try BibleVerse(
            reference: reference,
            text: "Sample verse."
        )

        let repository = InMemoryBibleRepository(verses: [verse])
        let catalog: any BibleCatalogRepository = repository

        let chapters = try await catalog.chapters(in: "EXO")

        #expect(chapters.isEmpty)
    }
    
    @Test
    func repositoryReturnsChapterVersesInAscendingOrder() async throws {
        let firstVerse = try BibleVerse(
            reference: BibleReference(
                bookID: "GEN",
                chapter: 1,
                verse: 1
            ),
            text: "First verse."
        )

        let secondVerse = try BibleVerse(
            reference: BibleReference(
                bookID: "GEN",
                chapter: 1,
                verse: 2
            ),
            text: "Second verse."
        )

        let repository = InMemoryBibleRepository(
            verses: [secondVerse, firstVerse]
        )

        let catalog: any BibleCatalogRepository = repository

        let returnedVerses = try await catalog.verses(
            in: "GEN",
            chapter: 1
        )

        #expect(returnedVerses == [firstVerse, secondVerse])
    }
    
    @Test
    func repositoryReturnsVersesOnlyForRequestedBookAndChapter() async throws {
        let references = [
            try BibleReference(bookID: "GEN", chapter: 1, verse: 1),
            try BibleReference(bookID: "GEN", chapter: 2, verse: 1),
            try BibleReference(bookID: "EXO", chapter: 1, verse: 1)
        ]

        let verses = try references.map { reference in
            try BibleVerse(
                reference: reference,
                text: "Sample verse."
            )
        }

        let repository = InMemoryBibleRepository(verses: verses)
        let catalog: any BibleCatalogRepository = repository

        let returnedVerses = try await catalog.verses(
            in: "GEN",
            chapter: 1
        )

        #expect(returnedVerses == [verses[0]])
    }
    
    @Test
    func repositoryReturnsEmptyArrayForChapterWithoutStoredVerses() async throws {
        let verse = try BibleVerse(
            reference: BibleReference(
                bookID: "GEN",
                chapter: 1,
                verse: 1
            ),
            text: "Sample verse."
        )

        let repository = InMemoryBibleRepository(verses: [verse])
        let catalog: any BibleCatalogRepository = repository

        let returnedVerses = try await catalog.verses(
            in: "GEN",
            chapter: 2
        )

        #expect(returnedVerses.isEmpty)
    }
}
