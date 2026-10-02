//
//  AppModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import BibleAI
import Foundation
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
            AppModel.Repositories(verses: verses, catalog: catalog, text: stored, passages: stored)
        })
        await model.start()
        guard let search = model.session?.referenceSearch else {
            Issue.record("Expected search to be composed with the loaded repositories")
            return
        }
        await search.search("John 3:16")
        #expect(search.state == .loaded(query: "John 3:16", verse: verse))
    }

    @Test
    @MainActor
    func startCreatesChatWithLoadedRepositoriesAndEngine() async throws {
        let reference = try BibleReference(bookID: "GEN", chapter: 1, verse: 1)
        let verse = try BibleVerse(reference: reference, text: "In the beginning God created the heaven and the earth.")
        let repository = InMemoryBibleRepository(
            verses: [verse],
            books: [try BibleBook(bookID: "GEN", name: "Genesis", canonicalOrder: 1)]
        )
        let appModel = AppModel(
            loadRepositories: {
                AppModel.Repositories(verses: repository, catalog: repository, text: repository, passages: repository)
            },
            chatEngine: .init(makeStreamer: { CannedStreamer() }, passageBudget: { 6_000 })
        )

        await appModel.start()
        guard let chat = appModel.session?.chat else {
            Issue.record("Expected ready state")
            return
        }
        await chat.send("Who created the heaven?").value

        let answer = try #require(chat.conversation.messages.last)
        #expect(answer.sources.first?.title == "Genesis 1:1", "Passages come from the loaded repository")
        #expect(chat.citations[answer.id]?.flatMap(\.items).map(\.status) == [.grounded])
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
                    text: repository,
                    passages: repository
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
                    text: repository,
                    passages: repository
                )
            }
        )

        await appModel.start()

        guard let catalogModel = appModel.session?.catalog else {
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
                    text: repository,
                    passages: repository
                )
            }
        )

        await appModel.start()

        guard let textSearch = appModel.session?.textSearch else {
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

@MainActor
struct AppModelLibraryTests {
    private static func entry(_ id: String) throws -> BibleCatalogEntry {
        BibleCatalogEntry(
            version: try BibleVersion(id: id, name: id, abbreviation: id, languageCode: "en", copyright: ""),
            manifest: ModelManifest(repository: "owner/repo", revision: id, files: [], host: .gitHubRelease)
        )
    }

    private func library(installed: Set<String>) throws -> BibleLibraryModel {
        let catalog = [try Self.entry("kjv"), try Self.entry("web")]
        var stores: [String: any LocalModelStoring] = [:]
        for entry in catalog {
            stores[entry.id] = FakeBibleStore(id: entry.id, installed: installed.contains(entry.id))
        }
        return BibleLibraryModel(catalog: catalog, stores: stores, defaults: InMemoryDefaults()) { entry, _ in
            LoadedBible(
                version: entry.version,
                repositories: AppModel.Repositories(repository: InMemoryBibleRepository(verses: [])),
                embeddingsURL: URL(fileURLWithPath: "/tmp/\(entry.id)/embeddings.bin")
            )
        }
    }

    @Test
    func withNoInstalledBibleTheAppNeedsAVersionThenOpensTheDownloadedOne() async throws {
        let library = try library(installed: [])
        let appModel = AppModel(library: library)

        await appModel.start()
        guard case .needsVersion = appModel.state else {
            Issue.record("Expected onboarding, got \(appModel.state)")
            return
        }

        await library.install("web").value
        await appModel.start()

        #expect(appModel.session?.version.id == "web")
        #expect(appModel.session?.embeddingsURL?.path == "/tmp/web/embeddings.bin")
    }

    @Test
    func switchingVersionReloadsTheModelsAndRemembersTheChoice() async throws {
        let library = try library(installed: ["kjv", "web"])
        let appModel = AppModel(library: library)
        await appModel.start()
        let first = try #require(appModel.session)
        #expect(first.version.id == "kjv")

        await appModel.switchVersion(to: "web")

        let second = try #require(appModel.session)
        #expect(second.version.id == "web")
        #expect(second.catalog !== first.catalog)
        #expect(second.chat === first.chat, "The chat continues across versions")
        #expect(library.activeVersionID == "web")
    }

    @Test
    func switchingToAMissingVersionKeepsTheCurrentOne() async throws {
        let library = try library(installed: ["kjv"])
        let appModel = AppModel(library: library)
        await appModel.start()

        await appModel.switchVersion(to: "web")

        #expect(appModel.session?.version.id == "kjv")
    }
}

@MainActor
extension AppModel {
    /// One installed version whose repositories come from `loadRepositories`.
    convenience init(
        loadRepositories: @escaping @Sendable () async throws -> Repositories,
        chatEngine: BibleChatModel.Engine? = nil
    ) {
        let entry = BibleCatalogEntry(
            version: try! BibleVersion(id: "kjv", name: "King James Version", abbreviation: "KJV", languageCode: "en", copyright: ""),
            manifest: ModelManifest(repository: "owner/repo", revision: "test", files: [], host: .gitHubRelease)
        )
        let library = BibleLibraryModel(
            catalog: [entry],
            stores: ["kjv": FakeBibleStore(id: "kjv", installed: true)],
            defaults: InMemoryDefaults()
        ) { entry, _ in
            LoadedBible(version: entry.version, repositories: try await loadRepositories(), embeddingsURL: nil)
        }
        self.init(library: library, chatEngine: chatEngine ?? .unavailable)
    }
}

private actor CountingRepositoryLoader {
    private let repository:
        any BibleRepository & BibleCatalogRepository & BibleTextSearchRepository & BiblePassageSearchRepository

    private var count = 0

    init(
        repository: any BibleRepository & BibleCatalogRepository & BibleTextSearchRepository & BiblePassageSearchRepository
    ) {
        self.repository = repository
    }

    func load() async throws
        -> any BibleRepository & BibleCatalogRepository & BibleTextSearchRepository & BiblePassageSearchRepository
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

/// Answers every prompt with one citation of Genesis 1:1.
private struct CannedStreamer: AIPromptStreaming {
    func streamResponse(to prompt: BibleStudyPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(prompt.isContentTransformation ? "created, heaven" : "God created them [Genesis 1:1].")
            continuation.finish()
        }
    }
}
