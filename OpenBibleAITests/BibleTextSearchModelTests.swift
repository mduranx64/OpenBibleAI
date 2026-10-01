import BibleDomain
import Testing

@testable import OpenBibleAI

@MainActor
struct BibleTextSearchModelTests {
    private func verse(_ number: Int, _ text: String) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(bookID: "JOH", chapter: 3, verse: number),
            text: text
        )
    }

    private func result(_ verses: [BibleVerse], total: Int? = nil) -> BibleTextSearchResult {
        BibleTextSearchResult(verses: verses, totalCount: total ?? verses.count)
    }

    @Test
    func successfulSearchPublishesResultForQuery() async throws {
        let expected = result([try verse(16, "For God so loved the world")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { _, _ in expected }
        )

        await model.search("loved")

        #expect(model.state == .loaded(query: "loved", result: expected))
    }

    @Test
    func searchPassesParsedQueryAndConfiguredLimit() async throws {
        let spy = TextSearchSpy()
        let model = BibleTextSearchModel(repository: spy, resultLimit: 7)

        await model.search("Love \"one another\"")

        #expect(await spy.queries == [try BibleTextQuery("Love \"one another\"")])
        #expect(await spy.limits == [7])
    }

    @Test(arguments: ["", "   ", "a", "\"\""])
    func tooShortQueriesNeverReachTheRepository(raw: String) async {
        let spy = TextSearchSpy()
        let model = BibleTextSearchModel(repository: spy)

        await model.search(raw)

        #expect(model.state == .tooShort)
        #expect(await spy.queries.isEmpty)
    }

    @Test
    func tooShortQuerySupersedesOlderResult() async throws {
        let model = BibleTextSearchModel(
            repository: TextSearchStub { _, _ in
                BibleTextSearchResult(verses: [], totalCount: 0)
            }
        )

        await model.search("loved")
        await model.search("a")

        #expect(model.state == .tooShort)
    }

    @Test
    func repositoryFailureIsPublishedWithQuery() async {
        let model = BibleTextSearchModel(
            repository: TextSearchStub { _, _ in throw TextSearchTestError.unavailable }
        )

        await model.search("loved")

        guard case let .failed(query, message) = model.state else {
            Issue.record("Expected failure")
            return
        }
        #expect(query == "loved")
        #expect(message.contains("Could not search"))
    }

    @Test
    func olderSearchFinishingLaterCannotOverwriteNewerResult() async throws {
        let gate = TextSearchGate()
        let newer = result([try verse(16, "newer")])
        let older = result([try verse(1, "older")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { query, _ in
                try await gate.value(for: query, fallback: newer)
            }
        )

        let firstTask = Task { await model.search("first") }
        await gate.waitUntilStarted()
        await model.search("second")
        #expect(model.state == .loaded(query: "second", result: newer))

        await gate.finish(.success(older))
        await firstTask.value

        #expect(model.state == .loaded(query: "second", result: newer))
    }

    @Test
    func olderFailureCannotOverwriteNewerResult() async throws {
        let gate = TextSearchGate()
        let newer = result([try verse(16, "newer")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { query, _ in
                try await gate.value(for: query, fallback: newer)
            }
        )

        let firstTask = Task { await model.search("first") }
        await gate.waitUntilStarted()
        await model.search("second")

        await gate.finish(.failure(TextSearchTestError.unavailable))
        await firstTask.value

        #expect(model.state == .loaded(query: "second", result: newer))
    }

    @Test(arguments: [false, true])
    func cancelledSearchSettlesToIdleEvenIfRepositorySucceeds(fails: Bool) async throws {
        let gate = TextSearchGate()
        let late = result([try verse(16, "late")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { query, _ in
                try await gate.value(for: query, fallback: late)
            }
        )

        let task = Task { await model.search("loved") }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.finish(fails ? .failure(TextSearchTestError.unavailable) : .success(late))
        await task.value

        #expect(model.state == .idle)
    }

    @Test
    func resetInvalidatesPendingSearch() async throws {
        let gate = TextSearchGate()
        let late = result([try verse(16, "late")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { query, _ in
                try await gate.value(for: query, fallback: late)
            }
        )

        let task = Task { await model.search("loved") }
        await gate.waitUntilStarted()
        model.reset()
        await gate.finish(.success(late))
        await task.value

        #expect(model.state == .idle)
    }

    @Test
    func alreadyCancelledInvocationLeavesStateUntouched() async throws {
        let expected = result([try verse(16, "x")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { _, _ in expected }
        )
        await model.search("loved")

        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.search("another")
        }.value

        #expect(model.state == .loaded(query: "loved", result: expected))
    }

    @Test
    func submitSupersedesOlderSubmissionAndCancelStopsOwnedTask() async throws {
        let gate = TextSearchGate()
        let newer = result([try verse(16, "newer")])
        let model = BibleTextSearchModel(
            repository: TextSearchStub { query, _ in
                try await gate.value(for: query, fallback: newer)
            }
        )

        let first = model.submit("first")
        await gate.waitUntilStarted()
        let second = model.submit("second")
        await second.value
        await gate.finish(.success(result([try verse(1, "older")])))
        await first.value

        #expect(model.state == .loaded(query: "second", result: newer))

        model.cancel()

        #expect(model.state == .idle)
    }
}

private enum TextSearchTestError: Error { case unavailable }

private struct TextSearchStub: BibleTextSearchRepository {
    let run: @Sendable (BibleTextQuery, Int) async throws -> BibleTextSearchResult

    func search(_ query: BibleTextQuery, limit: Int) async throws -> BibleTextSearchResult {
        try await run(query, limit)
    }
}

private actor TextSearchSpy: BibleTextSearchRepository {
    private(set) var queries: [BibleTextQuery] = []
    private(set) var limits: [Int] = []

    func search(_ query: BibleTextQuery, limit: Int) async throws -> BibleTextSearchResult {
        queries.append(query)
        limits.append(limit)
        return BibleTextSearchResult(verses: [], totalCount: 0)
    }
}

/// Suspends only the first request and deliberately ignores cancellation.
private actor TextSearchGate {
    private(set) var requestCount = 0
    private var pending: CheckedContinuation<BibleTextSearchResult, any Error>?
    private var started: [CheckedContinuation<Void, Never>] = []

    func value(
        for query: BibleTextQuery,
        fallback: BibleTextSearchResult
    ) async throws -> BibleTextSearchResult {
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

    func finish(_ result: Result<BibleTextSearchResult, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}
