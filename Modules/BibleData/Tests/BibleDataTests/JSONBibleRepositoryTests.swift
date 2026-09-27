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
}
