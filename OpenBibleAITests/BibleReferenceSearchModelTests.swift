import Testing
import BibleDomain
@testable import OpenBibleAI

@MainActor
struct BibleReferenceSearchModelTests {
    private func books() throws -> [BibleBook] {
        try [BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)]
    }

    private func verse(_ number: Int = 16) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(bookID: "JOH", chapter: 3, verse: number),
            text: "Stored test verse \(number)"
        )
    }

    @Test func resolvesStoredVerse() async throws {
        let expected = try verse()
        let catalog = InMemoryBibleRepository(verses: [], books: try books())
        let repository = InMemoryBibleRepository(verses: [expected])
        let model = BibleReferenceSearchModel(catalog: catalog, verses: repository)
        #expect(model.state == .idle)
        await model.search("john 3:16")
        #expect(model.state == .loaded(query: "john 3:16", verse: expected))
    }

    @Test(arguments: ["John", "Unknown 3:16", "John 0:16", "John 3:0"])
    func inputErrorsDoNotRequestAVerse(_ query: String) async throws {
        let expected = try verse()
        let repository = SearchVerseSpy(storedVerse: expected)
        let catalog = InMemoryBibleRepository(verses: [], books: try books())
        let model = BibleReferenceSearchModel(catalog: catalog, verses: repository)
        await model.search(query)
        guard case let .failed(failedQuery, message) = model.state else {
            Issue.record("Expected input feedback")
            return
        }
        #expect(failedQuery == query)
        #expect(!message.isEmpty)
        #expect(await repository.requestCount == 0)
    }

    @Test func missingVerseReportsFailureAndCanRetry() async throws {
        let expected = try verse()
        let repository = InMemoryBibleRepository(verses: [expected], books: try books())
        let model = BibleReferenceSearchModel(catalog: repository, verses: repository)
        await model.search("John 999:999")
        #expect(model.state == .failed(
            query: "John 999:999", message: "This verse is not available in the loaded Bible."
        ))
        await model.search("John 3:16")
        #expect(model.state == .loaded(query: "John 3:16", verse: expected))
    }

    @Test func catalogFailureDoesNotRequestAVerse() async throws {
        let expected = try verse()
        let repository = SearchVerseSpy(storedVerse: expected)
        let model = BibleReferenceSearchModel(
            catalog: SearchCatalogStub { throw SearchTestError.unavailable },
            verses: repository
        )
        await model.search("John 3:16")
        guard case let .failed(query, message) = model.state else {
            Issue.record("Expected catalog failure")
            return
        }
        #expect(query == "John 3:16")
        #expect(message.contains("unavailable"))
        #expect(await repository.requestCount == 0)
    }

    @Test func verseRepositoryFailureIsReported() async throws {
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in throw SearchTestError.unavailable }
        )
        await model.search("John 3:16")
        guard case let .failed(query, message) = model.state else {
            Issue.record("Expected verse repository failure")
            return
        }
        #expect(query == "John 3:16")
        #expect(message.contains("unavailable"))
    }

    @Test func rejectsMismatchedRepositoryResult() async throws {
        let otherVerse = try verse(17)
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in otherVerse }
        )
        await model.search("John 3:16")
        #expect(model.state == .failed(
            query: "John 3:16", message: "The repository returned a different verse. Please try again."
        ))
    }

    @Test(arguments: [false, true])
    func newerSearchWinsOverLateVerseCompletion(_ fail: Bool) async throws {
        let olderVerse = try verse()
        let newerVerse = try verse(17)
        let gate = SearchGate<BibleVerse>()
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in try await gate.value(fallback: newerVerse) }
        )
        let older = Task { await model.search("John 3:16") }
        await gate.waitUntilStarted()
        #expect(model.state == .loading(query: "John 3:16"))
        await model.search("John 3:17")
        await gate.finish(fail ? .failure(SearchTestError.unavailable) : .success(olderVerse))
        await older.value
        #expect(model.state == .loaded(query: "John 3:17", verse: newerVerse))
    }

    @Test(arguments: [false, true])
    func newerSearchWinsOverLateCatalogCompletion(_ fail: Bool) async throws {
        let catalog = try books()
        let expected = try verse(17)
        let gate = SearchGate<[BibleBook]>()
        let model = BibleReferenceSearchModel(
            catalog: SearchCatalogStub { try await gate.value(fallback: catalog) },
            verses: InMemoryBibleRepository(verses: [expected])
        )
        let older = Task { await model.search("John 3:16") }
        await gate.waitUntilStarted()
        #expect(model.state == .loading(query: "John 3:16"))
        await model.search("John 3:17")
        await gate.finish(fail ? .failure(SearchTestError.unavailable) : .success(catalog))
        await older.value
        #expect(model.state == .loaded(query: "John 3:17", verse: expected))
    }

    @Test(arguments: [false, true])
    func cancellationSuppressesNoncooperativeVerseCompletion(_ fail: Bool) async throws {
        let expected = try verse()
        let gate = SearchGate<BibleVerse>()
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in try await gate.value(fallback: expected) }
        )
        let task = Task { await model.search("John 3:16") }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.finish(fail ? .failure(SearchTestError.unavailable) : .success(expected))
        await task.value
        #expect(model.state == .idle)
    }

    @Test func cancellationDuringCatalogLoadDoesNotRequestAVerse() async throws {
        let catalog = try books()
        let expected = try verse()
        let catalogGate = SearchGate<[BibleBook]>()
        let repository = SearchVerseSpy(storedVerse: expected)
        let model = BibleReferenceSearchModel(
            catalog: SearchCatalogStub { try await catalogGate.value(fallback: catalog) },
            verses: repository
        )
        let task = Task { await model.search("John 3:16") }
        await catalogGate.waitUntilStarted()
        task.cancel()
        await catalogGate.finish(.success(catalog))
        await task.value
        #expect(model.state == .idle)
        #expect(await repository.requestCount == 0)
    }

    @Test func alreadyCancelledSearchDoesNotReplaceLoadedState() async throws {
        let expected = try verse()
        let repository = SearchVerseSpy(storedVerse: expected)
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: repository
        )
        await model.search("John 3:16")
        let cancelled = Task { await model.search("John 3:17") }
        // Both test and task use MainActor, so cancellation precedes task entry.
        cancelled.cancel()
        await cancelled.value
        #expect(model.state == .loaded(query: "John 3:16", verse: expected))
        #expect(await repository.requestCount == 1)
    }

    @Test func olderCancellationCannotClearNewerSuccess() async throws {
        let expected = try verse(17)
        let gate = SearchGate<BibleVerse>()
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in try await gate.value(fallback: expected) }
        )
        let older = Task { await model.search("John 3:16") }
        await gate.waitUntilStarted()
        older.cancel()
        await model.search("John 3:17")
        await gate.finish(.failure(CancellationError()))
        await older.value
        #expect(model.state == .loaded(query: "John 3:17", verse: expected))
    }

    @Test func resetInvalidatesAnInFlightResult() async throws {
        let expected = try verse()
        let gate = SearchGate<BibleVerse>()
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in try await gate.value(fallback: expected) }
        )
        let task = Task { await model.search("John 3:16") }
        await gate.waitUntilStarted()
        model.reset()
        #expect(model.state == .idle)
        await gate.finish(.success(expected))
        await task.value
        #expect(model.state == .idle)
    }

    @Test func invalidNewInputSupersedesPendingSuccess() async throws {
        let expected = try verse()
        let gate = SearchGate<BibleVerse>()
        let model = BibleReferenceSearchModel(
            catalog: InMemoryBibleRepository(verses: [], books: try books()),
            verses: SearchVerseStub { _ in try await gate.value(fallback: expected) }
        )
        let task = Task { await model.search("John 3:16") }
        await gate.waitUntilStarted()
        await model.search("John")
        let failure = model.state
        guard case .failed = failure else {
            await gate.finish(.success(expected))
            await task.value
            Issue.record("Expected invalid input feedback")
            return
        }
        await gate.finish(.success(expected))
        await task.value
        #expect(model.state == failure)
    }
}

private enum SearchTestError: Error { case unavailable }

private struct SearchCatalogStub: BibleCatalogRepository {
    let load: @Sendable () async throws -> [BibleBook]
    func books() async throws -> [BibleBook] { try await load() }
    func chapters(in bookID: String) async throws -> [Int] { throw SearchTestError.unavailable }
    func verses(in bookID: String, chapter: Int) async throws -> [BibleVerse] {
        throw SearchTestError.unavailable
    }
}

private struct SearchVerseStub: BibleRepository {
    let lookup: @Sendable (BibleReference) async throws -> BibleVerse
    func verse(at reference: BibleReference) async throws -> BibleVerse { try await lookup(reference) }
}

private actor SearchVerseSpy: BibleRepository {
    let storedVerse: BibleVerse
    private(set) var requestCount = 0

    init(storedVerse: BibleVerse) { self.storedVerse = storedVerse }

    func verse(at reference: BibleReference) async throws -> BibleVerse {
        requestCount += 1
        return storedVerse
    }
}

/// Suspends only the first request and deliberately ignores cancellation.
private actor SearchGate<Value: Sendable> {
    private(set) var requestCount = 0
    private var pending: CheckedContinuation<Value, any Error>?
    private var started: [CheckedContinuation<Void, Never>] = []

    func value(fallback: Value) async throws -> Value {
        requestCount += 1
        guard requestCount == 1 else { return fallback }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            for waiter in started { waiter.resume() }
            started.removeAll()
        }
    }

    func waitUntilStarted() async {
        guard requestCount == 0 else { return }
        await withCheckedContinuation { started.append($0) }
    }

    func finish(_ result: Result<Value, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}
