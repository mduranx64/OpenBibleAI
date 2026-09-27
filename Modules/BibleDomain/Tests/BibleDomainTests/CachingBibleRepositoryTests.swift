//
//  CachingBibleRepositoryTests.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

import Testing
import BibleDomain

struct CachingBibleRepositoryTests {
    @Test
    func repeatedLookupUsesCachedVerse() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let expectedVerse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )

        let baseRepository = CountingBibleRepository(
            verse: expectedVerse
        )
        let repository = CachingBibleRepository(
            base: baseRepository
        )

        let firstResult = try await repository.verse(
            at: reference
        )
        let secondResult = try await repository.verse(
            at: reference
        )
        let requestCount = await baseRepository.requestCount()

        #expect(firstResult == expectedVerse)
        #expect(secondResult == expectedVerse)
        #expect(requestCount == 1)
    }
    
    @Test
    func concurrentLookupLoadsBaseOnlyOnce() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let expectedVerse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )

        let baseRepository = CountingBibleRepository(
            verse: expectedVerse,
            delay: .milliseconds(100)
        )
        let repository = CachingBibleRepository(
            base: baseRepository
        )

        async let firstResult = repository.verse(at: reference)
        async let secondResult = repository.verse(at: reference)

        let results = try await (
            firstResult,
            secondResult
        )
        let requestCount = await baseRepository.requestCount()

        #expect(results.0 == expectedVerse)
        #expect(results.1 == expectedVerse)
        #expect(requestCount == 1)
    }
    
    @Test
    func failedLookupCanBeRetried() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let expectedVerse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )

        let baseRepository = FailingOnceBibleRepository(
            verse: expectedVerse
        )
        let repository = CachingBibleRepository(
            base: baseRepository
        )

        await #expect(
            throws: FailingOnceBibleRepository.TestError
                .firstRequestFailed
        ) {
            try await repository.verse(at: reference)
        }

        let retriedVerse = try await repository.verse(
            at: reference
        )
        let requestCount = await baseRepository.requestCount()

        #expect(retriedVerse == expectedVerse)
        #expect(requestCount == 2)
    }
}

private actor CountingBibleRepository: BibleRepository {
    private let storedVerse: BibleVerse
    private let delay: Duration
    private var count = 0

    init(
        verse: BibleVerse,
        delay: Duration = .zero
    ) {
        self.storedVerse = verse
        self.delay = delay
    }

    func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        count += 1

        try await Task.sleep(for: delay)

        return storedVerse
    }

    func requestCount() -> Int {
        count
    }
}

private actor FailingOnceBibleRepository: BibleRepository {
    enum TestError: Error, Equatable, Sendable {
        case firstRequestFailed
    }

    private let storedVerse: BibleVerse
    private var count = 0

    init(verse: BibleVerse) {
        self.storedVerse = verse
    }

    func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        count += 1

        if count == 1 {
            throw TestError.firstRequestFailed
        }

        return storedVerse
    }

    func requestCount() -> Int {
        count
    }
}
