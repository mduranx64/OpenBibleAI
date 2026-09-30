//
//  JSONBibleRepository.swift
//  BibleData
//
//  Created by Miguel Duran on 27-09-26.
//

import Foundation
import Testing
import BibleData
import BibleDomain

struct JSONBibleRepositoryTests {
    @Test
    func repositoryDecodesAndReturnsVerse() async throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 1,
                "text": "In the beginning"
            }
        ]
        """

        let repository = try JSONBibleRepository(
            data: Data(json.utf8)
        )

        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try await repository.verse(
            at: reference
        )

        #expect(verse.reference == reference)
        #expect(verse.text == "In the beginning")
    }
    
    @Test
    func repositoryRejectsDuplicateReferences() throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 1,
                "text": "First value"
            },
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 1,
                "text": "Duplicate value"
            }
        ]
        """

        let duplicateReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        #expect(
            throws: JSONBibleRepository.LoadError
                .duplicateReference(duplicateReference)
        ) {
            try JSONBibleRepository(
                data: Data(json.utf8)
            )
        }
    }
    
    @Test
    func repositoryRejectsInvalidDomainValues() {
        let json = """
        [
            {
                "book_id": "GEN",
                "chapter": 0,
                "verse": 1,
                "text": "Invalid chapter"
            }
        ]
        """

        #expect(
            throws: BibleReference.ValidationError
                .invalidChapter(0)
        ) {
            try JSONBibleRepository(
                data: Data(json.utf8)
            )
        }
    }
    
    @Test
    func repositoryLoadsVersesFromFile() async throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 1,
                "text": "In the beginning"
            }
        ]
        """

        let fileURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\(UUID()).json")

        try Data(json.utf8).write(to: fileURL)

        defer {
            try? FileManager.default.removeItem(
                at: fileURL
            )
        }

        let repository = try await JSONBibleRepository.load(
            from: fileURL
        )

        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try await repository.verse(
            at: reference
        )

        #expect(verse.text == "In the beginning")
    }
    
    @Test
    func repositoryReturnsProvidedBooksInCanonicalOrder() async throws {
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

        let repository = try JSONBibleRepository(
            data: Data("[]".utf8),
            books: [exodus, genesis]
        )

        let catalog: any BibleCatalogRepository = repository
        let returnedBooks = try await catalog.books()

        #expect(returnedBooks == [genesis, exodus])
    }
    
    @Test
    func repositoryLoadsBookMetadataAlongsideVerseFile() async throws {
        let genesis = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        let fileURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\(UUID()).json")

        try Data("[]".utf8).write(to: fileURL)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let repository = try await JSONBibleRepository.load(
            from: fileURL,
            books: [genesis]
        )

        let catalog: any BibleCatalogRepository = repository
        let returnedBooks = try await catalog.books()

        #expect(returnedBooks == [genesis])
    }
    
    @Test
    func repositoryReturnsChaptersFromDecodedVerses() async throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "chapter": 2,
                "verse": 1,
                "text": "Chapter two, verse one."
            },
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 1,
                "text": "Chapter one, verse one."
            },
            {
                "book_id": "GEN",
                "chapter": 2,
                "verse": 2,
                "text": "Chapter two, verse two."
            },
            {
                "book_id": "EXO",
                "chapter": 3,
                "verse": 1,
                "text": "Another book."
            }
        ]
        """

        let repository = try JSONBibleRepository(
            data: Data(json.utf8)
        )

        let catalog: any BibleCatalogRepository = repository
        let chapters = try await catalog.chapters(in: "GEN")

        #expect(chapters == [1, 2])
    }
    
    @Test
    func repositoryReturnsDecodedVersesForRequestedChapter() async throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 2,
                "text": "Second verse."
            },
            {
                "book_id": "GEN",
                "chapter": 2,
                "verse": 1,
                "text": "Another chapter."
            },
            {
                "book_id": "EXO",
                "chapter": 1,
                "verse": 1,
                "text": "Another book."
            },
            {
                "book_id": "GEN",
                "chapter": 1,
                "verse": 1,
                "text": "First verse."
            }
        ]
        """

        let repository = try JSONBibleRepository(
            data: Data(json.utf8)
        )

        let catalog: any BibleCatalogRepository = repository
        let verses = try await catalog.verses(
            in: "GEN",
            chapter: 1
        )

        let expectedVerses = [
            try BibleVerse(
                reference: BibleReference(
                    bookID: "GEN",
                    chapter: 1,
                    verse: 1
                ),
                text: "First verse."
            ),
            try BibleVerse(
                reference: BibleReference(
                    bookID: "GEN",
                    chapter: 1,
                    verse: 2
                ),
                text: "Second verse."
            )
        ]

        #expect(verses == expectedVerses)
    }
}
