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
    func startCreatesSearchWithSeparateCatalogAndVerseRepositories() async throws {
        let reference = try BibleReference(bookID: "JOH", chapter: 3, verse: 16)
        let verse = try BibleVerse(reference: reference, text: "Stored test verse")
        let catalog = InMemoryBibleRepository(verses: [], books: [
            try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)
        ])
        let stored = InMemoryBibleRepository(verses: [verse])
        let verses = CachingBibleRepository(base: stored)
        let model = AppModel(loadRepositories: {
            AppModel.Repositories(verses: verses, catalog: catalog, text: stored)
        })
        await model.start()
        guard case let .ready(_, _, search, _) = model.state else {
            Issue.record("Expected search to be composed with the loaded repositories")
            return
        }
        await search.search("John 3:16")
        #expect(search.state == .loaded(query: "John 3:16", verse: verse))
    }

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
            loadRepositories: {
                AppModel.Repositories(
                    verses: repository,
                    catalog: repository,
                    text: repository
                )
            }
        )

        guard case .idle = appModel.state else {
            Issue.record("Expected initial idle state")
            return
        }

        await appModel.start()

        guard case let .ready(readerModel, _, _, _) = appModel.state else {
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
            loadRepositories: {
                let repository = try await loader.load()

                return AppModel.Repositories(
                    verses: repository,
                    catalog: repository,
                    text: repository
                )
            }
        )

        async let firstStart: Void = appModel.start()
        async let secondStart: Void = appModel.start()

        await firstStart
        await secondStart

        let loadCount = await loader.loadCount()

        #expect(loadCount == 1)
    }
    
    @Test
    @MainActor
    func startCreatesCatalogWithLoadedRepository() async throws {
        let genesis = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        let repository = InMemoryBibleRepository(
            verses: [],
            books: [genesis]
        )

        let appModel = AppModel(
            loadRepositories: {
                AppModel.Repositories(
                    verses: CachingBibleRepository(base: repository),
                    catalog: repository,
                    text: repository
                )
            }
        )

        await appModel.start()

        guard case let .ready(_, catalogModel, _, _) = appModel.state else {
            Issue.record("Expected ready state")
            return
        }

        await catalogModel.loadBooks()

        #expect(catalogModel.state == .loaded([genesis]))
    }

    @Test
    @MainActor
    func startCreatesTextSearchWithLoadedRepository() async throws {
        let verse = try BibleVerse(
            reference: BibleReference(bookID: "GEN", chapter: 1, verse: 1),
            text: "In the beginning"
        )
        let repository = InMemoryBibleRepository(verses: [verse])
        let appModel = AppModel(
            loadRepositories: {
                AppModel.Repositories(
                    verses: repository,
                    catalog: repository,
                    text: repository
                )
            }
        )

        await appModel.start()

        guard case let .ready(_, _, _, textSearch) = appModel.state else {
            Issue.record("Expected ready state")
            return
        }

        await textSearch.search("beginning")

        guard case let .loaded(_, result) = textSearch.state else {
            Issue.record("Expected text search results")
            return
        }
        #expect(result.verses == [verse])
    }
}

private actor CountingRepositoryLoader {
    private let repository:
        any BibleRepository & BibleCatalogRepository & BibleTextSearchRepository

    private var count = 0

    init(
        repository: any BibleRepository & BibleCatalogRepository & BibleTextSearchRepository
    ) {
        self.repository = repository
    }

    func load() async throws
        -> any BibleRepository & BibleCatalogRepository & BibleTextSearchRepository
    {
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
