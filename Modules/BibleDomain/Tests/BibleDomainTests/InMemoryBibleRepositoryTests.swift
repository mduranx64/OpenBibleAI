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
}
