//
//  JSONBibleBookCatalogTests.swift
//  BibleData
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation
import Testing
import BibleData
import BibleDomain

struct JSONBibleBookCatalogTests {
    @Test
    func catalogDecodesBookMetadata() throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "name": "Genesis",
                "canonical_order": 1
            }
        ]
        """

        let catalog = try JSONBibleBookCatalog(
            data: Data(json.utf8)
        )

        let expectedBook = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        #expect(catalog.books == [expectedBook])
    }
    
    @Test
    func catalogRejectsInvalidCanonicalOrder() {
        let json = """
        [
            {
                "book_id": "GEN",
                "name": "Genesis",
                "canonical_order": 0
            }
        ]
        """

        #expect(
            throws: BibleBook.ValidationError
                .invalidCanonicalOrder(0)
        ) {
            try JSONBibleBookCatalog(
                data: Data(json.utf8)
            )
        }
    }
    
    @Test
    func catalogRejectsDuplicateBookIDs() {
        let json = """
        [
            {
                "book_id": "GEN",
                "name": "Genesis",
                "canonical_order": 1
            },
            {
                "book_id": "GEN",
                "name": "Genesis duplicate",
                "canonical_order": 2
            }
        ]
        """

        #expect(
            throws: JSONBibleBookCatalog.LoadError
                .duplicateBookID("GEN")
        ) {
            try JSONBibleBookCatalog(
                data: Data(json.utf8)
            )
        }
    }
    
    @Test
    func catalogLoadsBooksFromFile() async throws {
        let json = """
        [
            {
                "book_id": "GEN",
                "name": "Genesis",
                "canonical_order": 1
            }
        ]
        """

        let fileURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\(UUID()).json")

        try Data(json.utf8).write(to: fileURL)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let catalog = try await JSONBibleBookCatalog.load(
            from: fileURL
        )

        let expectedBook = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        #expect(catalog.books == [expectedBook])
    }
}
