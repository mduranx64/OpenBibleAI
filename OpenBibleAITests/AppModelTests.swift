//
//  AppModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Testing
import BibleDomain
@testable import OpenBibleAI

struct AppModelTests {
    @Test
    @MainActor
    func startCreatesReaderWithLoadedRepository() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let expectedVerse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )

        let repository = InMemoryBibleRepository(
            verses: [expectedVerse]
        )

        let appModel = AppModel(
            loadRepository: {
                repository
            }
        )

        guard case .idle = appModel.state else {
            Issue.record("Expected initial idle state")
            return
        }

        await appModel.start()

        guard case let .ready(readerModel) = appModel.state else {
            Issue.record("Expected ready state")
            return
        }

        await readerModel.load(reference: reference)

        #expect(
            readerModel.state ==
                .loaded(expectedVerse)
        )
    }
    
    @Test
    @MainActor
    func concurrentStartsLoadRepositoryOnlyOnce() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )
        let repository = InMemoryBibleRepository(
            verses: [verse]
        )

        let loader = CountingRepositoryLoader(
            repository: repository
        )
        let appModel = AppModel(
            loadRepository: {
                try await loader.load()
            }
        )

        async let firstStart: Void = appModel.start()
        async let secondStart: Void = appModel.start()

        await firstStart
        await secondStart

        let loadCount = await loader.loadCount()

        #expect(loadCount == 1)
    }
}

private actor CountingRepositoryLoader {
    private let repository: any BibleRepository
    private var count = 0

    init(repository: any BibleRepository) {
        self.repository = repository
    }

    func load() async throws -> any BibleRepository {
        count += 1

        try await Task.sleep(
            for: .milliseconds(100)
        )

        return repository
    }

    func loadCount() -> Int {
        count
    }
}
