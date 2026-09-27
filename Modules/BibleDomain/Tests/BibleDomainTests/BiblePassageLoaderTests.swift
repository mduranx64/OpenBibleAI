//
//  BiblePassageLoaderTests.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

import Testing
import BibleDomain

struct BiblePassageLoaderTests {
    @Test
    func loaderReturnsVersesInRequestedOrder() async throws {
        let firstReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let secondReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 2
        )
        let thirdReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 3
        )

        let firstVerse = try BibleVerse(
            reference: firstReference,
            text: "First verse"
        )
        let secondVerse = try BibleVerse(
            reference: secondReference,
            text: "Second verse"
        )
        let thirdVerse = try BibleVerse(
            reference: thirdReference,
            text: "Third verse"
        )

        let repository = InMemoryBibleRepository(
            verses: [
                firstVerse,
                secondVerse,
                thirdVerse
            ]
        )
        let loader = BiblePassageLoader(
            repository: repository
        )

        let verses = try await loader.verses(
            at: [
                thirdReference,
                firstReference,
                secondReference
            ]
        )

        #expect(
            verses == [
                thirdVerse,
                firstVerse,
                secondVerse
            ]
        )
    }
    
    @Test
    func loaderPropagatesRepositoryFailure() async throws {
        let existingReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let missingReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 2
        )

        let existingVerse = try BibleVerse(
            reference: existingReference,
            text: "First verse"
        )

        let repository = InMemoryBibleRepository(
            verses: [existingVerse]
        )
        let loader = BiblePassageLoader(
            repository: repository
        )

        await #expect(
            throws: InMemoryBibleRepository.LookupError
                .verseNotFound(missingReference)
        ) {
            try await loader.verses(
                at: [
                    existingReference,
                    missingReference
                ]
            )
        }
    }
}
