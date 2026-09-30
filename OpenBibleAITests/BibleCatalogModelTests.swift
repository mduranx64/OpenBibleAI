//
//  BibleCatalogModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Testing
import BibleDomain
@testable import OpenBibleAI

@Suite
@MainActor
struct BibleCatalogModelTests {
    @Test
    func catalogLoadsBooks() async throws {
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

        let model = BibleCatalogModel(
            repository: repository
        )

        #expect(model.state == .idle)

        await model.loadBooks()

        #expect(model.state == .loaded([genesis, exodus]))
    }
    
    @Test
    func catalogReportsRepositoryFailure() async {
        let model = BibleCatalogModel(
            repository: FailingCatalogRepository()
        )

        await model.loadBooks()

        guard case let .failed(message) = model.state else {
            Issue.record("Expected the catalog to enter the failed state")
            return
        }

        #expect(!message.isEmpty)
    }
    
    @Test
    func catalogReportsLoadingWhileRepositorySuspends() async {
        let repository = SuspendingCatalogRepository()
        let model = BibleCatalogModel(repository: repository)

        let loadingTask = Task { @MainActor in
            await model.loadBooks()
        }

        await repository.waitUntilRequestStarts()

        #expect(model.state == .loading)

        await repository.resume()
        await loadingTask.value

        #expect(model.state == .loaded([]))
    }
    
    @Test
    func catalogPreservesLoadedBooksWhenRefreshIsCancelled() async throws {
        let genesis = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        let repository = CancellingRefreshCatalogRepository(
            books: [genesis]
        )
        let model = BibleCatalogModel(repository: repository)

        await model.loadBooks()

        #expect(model.state == .loaded([genesis]))

        await model.loadBooks()

        #expect(model.state == .loaded([genesis]))
    }
    
    @Test
    func catalogLoadsChaptersForSelectedBook() async throws {
        let references = [
            try BibleReference(bookID: "GEN", chapter: 2, verse: 1),
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
        let model = BibleCatalogModel(repository: repository)

        #expect(model.chaptersState == .idle)

        await model.loadChapters(in: "GEN")

        #expect(
            model.chaptersState == .loaded(
                bookID: "GEN",
                chapters: [1, 2]
            )
        )
    }
    
    @Test
    func latestBookSelectionWinsWhenChapterLoadsFinishOutOfOrder() async {
        let repository = OutOfOrderChapterRepository()
        let model = BibleCatalogModel(repository: repository)

        let genesisTask = Task { @MainActor in
            await model.loadChapters(in: "GEN")
        }

        await repository.waitUntilGenesisRequestStarts()

        #expect(model.chaptersState == .loading(bookID: "GEN"))

        await model.loadChapters(in: "EXO")

        #expect(
            model.chaptersState == .loaded(
                bookID: "EXO",
                chapters: [3]
            )
        )

        await repository.completeGenesisRequest()
        await genesisTask.value

        #expect(
            model.chaptersState == .loaded(
                bookID: "EXO",
                chapters: [3]
            )
        )
    }
    
    @Test
    func catalogLoadsVersesForSelectedChapter() async throws {
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
        let model = BibleCatalogModel(repository: repository)

        #expect(model.versesState == .idle)

        await model.loadVerses(in: "GEN", chapter: 1)

        #expect(
            model.versesState == .loaded(
                bookID: "GEN",
                chapter: 1,
                verses: [firstVerse, secondVerse]
            )
        )
    }
    
    @Test
    func latestChapterSelectionWinsWhenVerseLoadsFinishOutOfOrder() async throws {
        let firstChapterVerse = try BibleVerse(
            reference: BibleReference(
                bookID: "GEN",
                chapter: 1,
                verse: 1
            ),
            text: "First chapter."
        )

        let secondChapterVerse = try BibleVerse(
            reference: BibleReference(
                bookID: "GEN",
                chapter: 2,
                verse: 1
            ),
            text: "Second chapter."
        )

        let repository = OutOfOrderVerseCatalogRepository(
            firstChapterVerse: firstChapterVerse,
            secondChapterVerse: secondChapterVerse
        )
        let model = BibleCatalogModel(repository: repository)

        let firstTask = Task { @MainActor in
            await model.loadVerses(in: "GEN", chapter: 1)
        }

        await repository.waitUntilFirstRequestStarts()

        #expect(
            model.versesState == .loading(
                bookID: "GEN",
                chapter: 1
            )
        )

        await model.loadVerses(in: "GEN", chapter: 2)

        #expect(
            model.versesState == .loaded(
                bookID: "GEN",
                chapter: 2,
                verses: [secondChapterVerse]
            )
        )

        await repository.completeFirstRequest()
        await firstTask.value

        #expect(
            model.versesState == .loaded(
                bookID: "GEN",
                chapter: 2,
                verses: [secondChapterVerse]
            )
        )
    }
    
    @Test
    func catalogFindsPreviousAndNextAvailableChapters() async throws {
        let references = [
            try BibleReference(bookID: "GEN", chapter: 1, verse: 1),
            try BibleReference(bookID: "GEN", chapter: 3, verse: 1),
            try BibleReference(bookID: "GEN", chapter: 5, verse: 1)
        ]

        let verses = try references.map { reference in
            try BibleVerse(
                reference: reference,
                text: "Sample verse."
            )
        }

        let repository = InMemoryBibleRepository(verses: verses)
        let model = BibleCatalogModel(repository: repository)

        await model.loadChapters(in: "GEN")

        #expect(
            model.previousChapter(in: "GEN", before: 3) == 1
        )

        #expect(
            model.nextChapter(in: "GEN", after: 3) == 5
        )
    }
    
    @Test
    func catalogReturnsNoDestinationBeyondChapterBoundaries() async throws {
        let references = [
            try BibleReference(bookID: "GEN", chapter: 1, verse: 1),
            try BibleReference(bookID: "GEN", chapter: 3, verse: 1)
        ]

        let verses = try references.map { reference in
            try BibleVerse(
                reference: reference,
                text: "Sample verse."
            )
        }

        let repository = InMemoryBibleRepository(verses: verses)
        let model = BibleCatalogModel(repository: repository)

        await model.loadChapters(in: "GEN")

        #expect(
            model.previousChapter(in: "GEN", before: 1) == nil
        )

        #expect(
            model.nextChapter(in: "GEN", after: 3) == nil
        )

        #expect(
            model.nextChapter(in: "GEN", after: 1) == 3
        )

        #expect(
            model.previousChapter(in: "GEN", before: 3) == 1
        )
    }
}

private struct FailingCatalogRepository: BibleCatalogRepository {
    enum TestError: Error {
        case unavailable
    }

    func books() async throws -> [BibleBook] {
        throw TestError.unavailable
    }

    func chapters(in bookID: String) async throws -> [Int] {
        throw TestError.unavailable
    }

    func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        throw TestError.unavailable
    }
}

private actor SuspendingCatalogRepository: BibleCatalogRepository {
    private var continuation:
        CheckedContinuation<[BibleBook], Never>?

    func books() async throws -> [BibleBook] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequestStarts() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume() {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(returning: [])
    }

    func chapters(in bookID: String) async throws -> [Int] {
        throw StubError.unexpectedCall
    }

    func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        throw StubError.unexpectedCall
    }

    private enum StubError: Error {
        case unexpectedCall
    }
}

private actor CancellingRefreshCatalogRepository:
    BibleCatalogRepository
{
    private let storedBooks: [BibleBook]
    private var hasLoaded = false

    init(books: [BibleBook]) {
        self.storedBooks = books
    }

    func books() async throws -> [BibleBook] {
        guard !hasLoaded else {
            throw CancellationError()
        }

        hasLoaded = true
        return storedBooks
    }

    func chapters(in bookID: String) async throws -> [Int] {
        throw StubError.unexpectedCall
    }

    func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        throw StubError.unexpectedCall
    }

    private enum StubError: Error {
        case unexpectedCall
    }
}

private actor OutOfOrderChapterRepository: BibleCatalogRepository {
    private var genesisContinuation:
        CheckedContinuation<[Int], Never>?

    func chapters(in bookID: String) async throws -> [Int] {
        switch bookID {
        case "GEN":
            return await withCheckedContinuation { continuation in
                genesisContinuation = continuation
            }

        case "EXO":
            return [3]

        default:
            throw StubError.unexpectedCall
        }
    }

    func waitUntilGenesisRequestStarts() async {
        while genesisContinuation == nil {
            await Task.yield()
        }
    }

    func completeGenesisRequest() {
        guard let continuation = genesisContinuation else {
            return
        }

        genesisContinuation = nil
        continuation.resume(returning: [1, 2])
    }

    func books() async throws -> [BibleBook] {
        throw StubError.unexpectedCall
    }

    func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        throw StubError.unexpectedCall
    }

    private enum StubError: Error {
        case unexpectedCall
    }
}

private actor OutOfOrderVerseCatalogRepository:
    BibleCatalogRepository
{
    private let firstChapterVerse: BibleVerse
    private let secondChapterVerse: BibleVerse

    private var firstContinuation:
        CheckedContinuation<[BibleVerse], Never>?

    init(
        firstChapterVerse: BibleVerse,
        secondChapterVerse: BibleVerse
    ) {
        self.firstChapterVerse = firstChapterVerse
        self.secondChapterVerse = secondChapterVerse
    }

    func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        guard bookID == "GEN" else {
            throw StubError.unexpectedCall
        }

        switch chapter {
        case 1:
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }

        case 2:
            return [secondChapterVerse]

        default:
            throw StubError.unexpectedCall
        }
    }

    func waitUntilFirstRequestStarts() async {
        while firstContinuation == nil {
            await Task.yield()
        }
    }

    func completeFirstRequest() {
        guard let continuation = firstContinuation else {
            return
        }

        firstContinuation = nil
        continuation.resume(returning: [firstChapterVerse])
    }

    func books() async throws -> [BibleBook] {
        throw StubError.unexpectedCall
    }

    func chapters(in bookID: String) async throws -> [Int] {
        throw StubError.unexpectedCall
    }

    private enum StubError: Error {
        case unexpectedCall
    }
}
