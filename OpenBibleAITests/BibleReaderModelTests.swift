//
//  BibleReaderModelTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 27-09-26.
//

import Testing
import BibleDomain
@testable import OpenBibleAI

@Suite
@MainActor
struct BibleReaderModelTests {
    @Test
    func readerLoadsVerse() async throws {
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
        let model = BibleReaderModel(
            repository: repository
        )

        #expect(model.state == .idle)

        await model.load(reference: reference)

        #expect(model.state == .loaded(expectedVerse))
    }
    
    @Test
    func readerReportsLoadingWhileRepositorySuspends() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let expectedVerse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )

        let repository = SuspendingBibleRepository(
            verse: expectedVerse
        )
        let model = BibleReaderModel(
            repository: repository
        )

        let loadingTask = Task { @MainActor in
            await model.load(reference: reference)
        }

        await repository.waitUntilRequestStarts()

        #expect(model.state == .loading)

        await repository.resume()
        await loadingTask.value

        #expect(model.state == .loaded(expectedVerse))
    }
    
    @Test
    func readerReportsRepositoryFailure() async throws {
        let missingReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let repository = InMemoryBibleRepository(
            verses: []
        )
        let model = BibleReaderModel(
            repository: repository
        )

        await model.load(reference: missingReference)

        guard case let .failed(message) = model.state else {
            Issue.record(
                "Expected the reader to enter the failed state"
            )
            return
        }

        #expect(!message.isEmpty)
    }
    
    @Test
    func readerRestoresPreviousStateWhenCancelled() async throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )
        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning"
        )

        let repository = CancellableBibleRepository(
            verse: verse
        )
        let model = BibleReaderModel(
            repository: repository
        )

        let loadingTask = Task { @MainActor in
            await model.load(reference: reference)
        }

        await repository.waitUntilRequestStarts()

        #expect(model.state == .loading)

        loadingTask.cancel()
        await loadingTask.value

        #expect(model.state == .idle)
    }
    
    @Test
    func latestRequestWinsWhenLoadsFinishOutOfOrder() async throws {
        let slowReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let fastReference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 2
        )

        let slowVerse = try BibleVerse(
            reference: slowReference,
            text: "Slow result"
        )

        let fastVerse = try BibleVerse(
            reference: fastReference,
            text: "Fast result"
        )

        let repository = OutOfOrderBibleRepository(
            slowReference: slowReference,
            slowVerse: slowVerse,
            fastVerse: fastVerse
        )

        let model = BibleReaderModel(repository: repository)

        let slowTask = Task {
            await model.load(reference: slowReference)
        }

        await repository.waitUntilSlowRequestStarts()

        let fastTask = Task {
            await model.load(reference: fastReference)
        }

        await fastTask.value

        await repository.completeSlowRequest()
        await slowTask.value

        #expect(model.state == .loaded(fastVerse))
    }
}

private actor SuspendingBibleRepository: BibleRepository {
    private let storedVerse: BibleVerse
    private var continuation:
        CheckedContinuation<BibleVerse, Never>?

    init(verse: BibleVerse) {
        self.storedVerse = verse
    }

    func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
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

        continuation.resume(
            returning: storedVerse
        )
    }
}

private actor CancellableBibleRepository:
    BibleRepository
{
    private let storedVerse: BibleVerse
    private var requestStarted = false

    init(verse: BibleVerse) {
        self.storedVerse = verse
    }

    func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        requestStarted = true

        try await Task.sleep(
            for: .seconds(10)
        )

        return storedVerse
    }

    func waitUntilRequestStarts() async {
        while !requestStarted {
            await Task.yield()
        }
    }
} 

private actor OutOfOrderBibleRepository: BibleRepository {
    private let slowReference: BibleReference
    private let slowVerse: BibleVerse
    private let fastVerse: BibleVerse

    private var slowRequestStarted = false

    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []

    private var slowRequestContinuation:
        CheckedContinuation<Void, Never>?

    init(
        slowReference: BibleReference,
        slowVerse: BibleVerse,
        fastVerse: BibleVerse
    ) {
        self.slowReference = slowReference
        self.slowVerse = slowVerse
        self.fastVerse = fastVerse
    }

    func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        guard reference == slowReference else {
            return fastVerse
        }

        slowRequestStarted = true

        let waiters = startWaiters
        startWaiters.removeAll()

        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            slowRequestContinuation = continuation
        }

        return slowVerse
    }

    func waitUntilSlowRequestStarts() async {
        guard !slowRequestStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func completeSlowRequest() {
        slowRequestContinuation?.resume()
        slowRequestContinuation = nil
    }
}
