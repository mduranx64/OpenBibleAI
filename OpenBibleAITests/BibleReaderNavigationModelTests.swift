import Foundation
import Testing
import BibleDomain
@testable import OpenBibleAI

@MainActor
struct BibleReaderNavigationModelTests {
    private func fixture() throws -> (InMemoryBibleRepository, BibleVerse) {
        let verse = try BibleVerse(
            reference: BibleReference(bookID: "JOH", chapter: 3, verse: 16),
            text: "Stored test verse"
        )
        let repository = InMemoryBibleRepository(verses: [verse], books: [
            try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)
        ])
        return (repository, verse)
    }

    private func withStore(
        _ body: (ReadingPositionStore) async throws -> Void
    ) async throws {
        try await body(ReadingPositionStore(defaults: InMemoryReadingPositionStorage()))
    }

    @Test func searchSelectsBookChapterVerseAndSavesOnlyChapter() async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let catalog = BibleCatalogModel(repository: repository)
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: catalog, store: store
            )
            await model.search("John 3:16").value
            #expect(model.selectedBookID == "JOH")
            #expect(model.selectedChapter == .init(bookID: "JOH", chapter: 3))
            #expect(model.selectedReference == verse.reference)
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 3))
            #expect(model.activeReference == nil)
            await catalog.loadVerses(in: "JOH", chapter: 3)
            #expect(model.activeReference == verse.reference)
            await catalog.loadVerses(in: "JOH", chapter: 4)
            #expect(model.activeReference == nil)
        }
    }

    @Test(arguments: ["John", "Unknown 3:16", "John 99:99"])
    func failedSearchPreservesSelectionAndSavedPosition(_ query: String) async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: BibleCatalogModel(repository: repository), store: store
            )
            await model.search("John 3:16").value
            await model.search(query).value
            #expect(model.selectedReference == verse.reference)
            #expect(model.selectedChapter == .init(bookID: "JOH", chapter: 3))
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 3))
        }
    }

    @Test func chapterAndBookSelectionClearVerseAndCancelSearch() async throws {
        try await withStore { store in
            let (repository, _) = try fixture()
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: BibleCatalogModel(repository: repository), store: store
            )
            await model.search("John 3:16").value
            model.selectChapter(4, in: "JOH")
            #expect(model.selectedReference == nil)
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 4))
            model.selectBook("GEN")
            #expect(model.selectedBookID == "GEN")
            #expect(model.selectedChapter == nil)
            #expect(model.selectedReference == nil)
            // Book selection alone must not overwrite the last saved chapter.
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 4))
        }
    }

    @Test(arguments: ["book", "chapter", "verse", "cancel"])
    func userActionInvalidatesDelayedSearch(_ action: String) async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let delayed = NavigationDelayedVerse(verse: verse)
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: delayed),
                catalog: BibleCatalogModel(repository: repository), store: store
            )
            model.selectChapter(3, in: "JOH")
            let pending = model.search("John 3:16")
            await delayed.waitUntilStarted()
            switch action {
            case "book": model.selectBook("GEN")
            case "chapter": model.selectChapter(4, in: "JOH")
            case "verse": model.selectVerse(try BibleReference(bookID: "JOH", chapter: 3, verse: 17))
            default: model.cancelSearch()
            }
            let selectedBook = model.selectedBookID
            let selectedChapter = model.selectedChapter
            let selectedVerse = model.selectedReference
            let saved = try store.load()
            await delayed.finish()
            await pending.value
            #expect(model.selectedBookID == selectedBook)
            #expect(model.selectedChapter == selectedChapter)
            #expect(model.selectedReference == selectedVerse)
            #expect(try store.load() == saved)
        }
    }

    @Test func openSelectsBookChapterVerseAndSavesOnlyChapter() async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: BibleCatalogModel(repository: repository), store: store
            )
            let revision = model.selectionRevision
            model.open(verse)
            #expect(model.selectedBookID == "JOH")
            #expect(model.selectedChapter == .init(bookID: "JOH", chapter: 3))
            #expect(model.selectedReference == verse.reference)
            #expect(model.selectionRevision == revision + 1)
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 3))
        }
    }

    @Test func openReferenceSelectsAndSavesLikeOpeningAVerse() async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: BibleCatalogModel(repository: repository), store: store
            )
            model.open(verse.reference)
            #expect(model.selectedChapter == .init(bookID: "JOH", chapter: 3))
            #expect(model.selectedReference == verse.reference)
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 3))
        }
    }

    @Test func openInvalidatesDelayedReferenceSearchAndRestoration() async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let other = try BibleVerse(
                reference: BibleReference(bookID: "JOH", chapter: 1, verse: 1),
                text: "Other verse"
            )
            let delayed = NavigationDelayedVerse(verse: verse)
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: delayed),
                catalog: BibleCatalogModel(repository: repository), store: store
            )
            let pending = model.search("John 3:16")
            await delayed.waitUntilStarted()
            model.open(other)
            await delayed.finish()
            await pending.value
            #expect(model.selectedReference == other.reference)
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 1))
        }
    }

    // MARK: Chapter and verse stepping

    /// GEN 1–2, EXO with no verses (an incomplete dataset), LEV 1–2.
    private func steppingFixture() throws -> InMemoryBibleRepository {
        func verse(_ book: String, _ chapter: Int) throws -> BibleVerse {
            try BibleVerse(
                reference: BibleReference(bookID: book, chapter: chapter, verse: 1),
                text: "\(book) \(chapter):1"
            )
        }
        return InMemoryBibleRepository(
            verses: try [verse("GEN", 1), verse("GEN", 2), verse("LEV", 1), verse("LEV", 2)],
            books: [
                try BibleBook(bookID: "GEN", name: "Genesis", canonicalOrder: 1),
                try BibleBook(bookID: "EXO", name: "Exodus", canonicalOrder: 2),
                try BibleBook(bookID: "LEV", name: "Leviticus", canonicalOrder: 3)
            ]
        )
    }

    private func steppingModel(
        _ repository: some BibleCatalogRepository & BibleRepository,
        store: ReadingPositionStore,
        at bookID: String,
        chapter: Int
    ) async -> (BibleReaderNavigationModel, BibleCatalogModel) {
        let catalog = BibleCatalogModel(repository: repository)
        await catalog.loadBooks()
        let model = BibleReaderNavigationModel(
            search: BibleReferenceSearchModel(catalog: repository, verses: repository),
            catalog: catalog, store: store
        )
        model.selectChapter(chapter, in: bookID)
        await catalog.loadChapters(in: bookID)
        return (model, catalog)
    }

    @Test func nextChapterStaysWithinBookWhenPossible() async throws {
        try await withStore { store in
            let (model, _) = try await steppingModel(steppingFixture(), store: store, at: "GEN", chapter: 1)
            #expect(model.canGoToNextChapter)
            await model.goToNextChapter()
            #expect(model.selectedChapter == .init(bookID: "GEN", chapter: 2))
            #expect(try store.load() == ReadingPosition(bookID: "GEN", chapter: 2))
        }
    }

    @Test func nextChapterCrossesToFirstChapterOfNextNonEmptyBook() async throws {
        try await withStore { store in
            let (model, _) = try await steppingModel(steppingFixture(), store: store, at: "GEN", chapter: 2)
            #expect(model.canGoToNextChapter)
            await model.goToNextChapter()
            #expect(model.selectedBookID == "LEV")
            #expect(model.selectedChapter == .init(bookID: "LEV", chapter: 1))
            #expect(model.selectedReference == nil)
            #expect(try store.load() == ReadingPosition(bookID: "LEV", chapter: 1))
        }
    }

    @Test func previousChapterCrossesToLastChapterOfPreviousNonEmptyBook() async throws {
        try await withStore { store in
            let (model, _) = try await steppingModel(steppingFixture(), store: store, at: "LEV", chapter: 1)
            #expect(model.canGoToPreviousChapter)
            await model.goToPreviousChapter()
            #expect(model.selectedChapter == .init(bookID: "GEN", chapter: 2))
            #expect(try store.load() == ReadingPosition(bookID: "GEN", chapter: 2))
        }
    }

    @Test func steppingStopsAtTheFirstAndLastChapterOfTheBible() async throws {
        try await withStore { store in
            let repository = try steppingFixture()
            let (first, _) = await steppingModel(repository, store: store, at: "GEN", chapter: 1)
            #expect(!first.canGoToPreviousChapter)
            await first.goToPreviousChapter()
            #expect(first.selectedChapter == .init(bookID: "GEN", chapter: 1))

            let (last, _) = await steppingModel(repository, store: store, at: "LEV", chapter: 2)
            #expect(!last.canGoToNextChapter)
            await last.goToNextChapter()
            #expect(last.selectedChapter == .init(bookID: "LEV", chapter: 2))
            #expect(try store.load() == ReadingPosition(bookID: "LEV", chapter: 2))
        }
    }

    @Test func newerChapterChoiceWinsOverPendingCrossBookStep() async throws {
        try await withStore { store in
            let base = try steppingFixture()
            let delayed = SteppingDelayedCatalog(base: base, delayedBookID: "EXO")
            let (model, _) = await steppingModel(delayed, store: store, at: "GEN", chapter: 2)

            let stepping = Task { await model.goToNextChapter() }
            await delayed.waitUntilStarted()
            model.selectChapter(1, in: "GEN")
            await delayed.finish()
            await stepping.value

            #expect(model.selectedChapter == .init(bookID: "GEN", chapter: 1))
            #expect(try store.load() == ReadingPosition(bookID: "GEN", chapter: 1))
        }
    }

    @Test func verseSteppingStartsAtFirstVerseAndStopsAtChapterEdges() async throws {
        try await withStore { store in
            let verses = try (1...3).map {
                try BibleVerse(reference: BibleReference(bookID: "JOH", chapter: 3, verse: $0), text: "v\($0)")
            }
            let repository = InMemoryBibleRepository(verses: verses, books: [
                try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)
            ])
            let catalog = BibleCatalogModel(repository: repository)
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: catalog, store: store
            )
            model.selectChapter(3, in: "JOH")

            model.selectAdjacentVerse(1)
            #expect(model.selectedReference == nil, "No chapter rows loaded yet")

            await catalog.loadVerses(in: "JOH", chapter: 3)
            let revision = model.selectionRevision
            model.selectAdjacentVerse(1)
            #expect(model.selectedReference == verses[0].reference)
            #expect(model.selectionRevision == revision + 1)
            model.selectAdjacentVerse(1)
            model.selectAdjacentVerse(1)
            model.selectAdjacentVerse(1)
            #expect(model.selectedReference == verses[2].reference)
            model.selectAdjacentVerse(-1)
            #expect(model.selectedReference == verses[1].reference)
            model.selectAdjacentVerse(-1)
            model.selectAdjacentVerse(-1)
            #expect(model.selectedReference == verses[0].reference)
        }
    }

    @Test func chapterNumbersLookupDoesNotChangeChapterListState() async throws {
        let repository = try steppingFixture()
        let catalog = BibleCatalogModel(repository: repository)
        await catalog.loadChapters(in: "GEN")
        let before = catalog.chaptersState

        let levChapters = try await catalog.chapterNumbers(in: "LEV")

        #expect(levChapters == [1, 2])
        #expect(catalog.chaptersState == before)
    }

    @Test func restoresChapterWithoutSelectingVerse() async throws {
        try await withStore { store in
            let (repository, _) = try fixture()
            try store.save(ReadingPosition(bookID: "JOH", chapter: 3))
            let catalog = BibleCatalogModel(repository: repository)
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: catalog, store: store
            )
            await catalog.loadBooks()
            await model.restoreReadingPosition()
            #expect(model.selectedChapter == .init(bookID: "JOH", chapter: 3))
            #expect(model.selectedReference == nil)
        }
    }

    @Test func delayedRestorationCannotReplaceSuccessfulSearch() async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            try store.save(ReadingPosition(bookID: "JOH", chapter: 2))
            let delayed = NavigationDelayedCatalog(books: try await repository.books())
            let catalog = BibleCatalogModel(repository: delayed)
            await catalog.loadBooks()
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: catalog, store: store
            )
            let restoring = Task { await model.restoreReadingPosition() }
            await delayed.waitUntilStarted()
            await model.search("John 3:16").value
            await delayed.finish()
            await restoring.value
            #expect(model.selectedReference == verse.reference)
            #expect(model.selectedChapter == .init(bookID: "JOH", chapter: 3))
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 3))
        }
    }

    @Test func unavailableSavedChapterLeavesSelectionEmpty() async throws {
        try await withStore { store in
            let (repository, _) = try fixture()
            let saved = try ReadingPosition(bookID: "JOH", chapter: 99)
            try store.save(saved)
            let catalog = BibleCatalogModel(repository: repository)
            await catalog.loadBooks()
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: catalog, store: store
            )
            await model.restoreReadingPosition()
            #expect(model.selectedBookID == nil)
            #expect(model.selectedChapter == nil)
            #expect(model.selectedReference == nil)
            #expect(try store.load() == saved)
        }
    }

    @Test func deselectionPreservesPendingSearchSelectionUntilRowsLoad() async throws {
        try await withStore { store in
            let (repository, verse) = try fixture()
            let catalog = BibleCatalogModel(repository: repository)
            let model = BibleReaderNavigationModel(
                search: BibleReferenceSearchModel(catalog: repository, verses: repository),
                catalog: catalog, store: store
            )
            await model.search("John 3:16").value
            model.deselectVerse()
            #expect(model.selectedReference == verse.reference)
            await catalog.loadVerses(in: "JOH", chapter: 3)
            model.deselectVerse()
            #expect(model.selectedReference == nil)
            #expect(try store.load() == ReadingPosition(bookID: "JOH", chapter: 3))
        }
    }
}

/// An in-memory `ReadingPositionStorage` so tests don't touch the real
/// `UserDefaults` or leave suite files behind on disk.
private final class InMemoryReadingPositionStorage: ReadingPositionStorage {
    private var storage: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}

private actor NavigationDelayedVerse: BibleRepository {
    let stored: BibleVerse
    private var pending: CheckedContinuation<BibleVerse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(verse: BibleVerse) { stored = verse }
    func verse(at reference: BibleReference) async throws -> BibleVerse {
        await withCheckedContinuation {
            pending = $0
            waiter?.resume()
            waiter = nil
        }
    }
    func waitUntilStarted() async {
        guard pending == nil else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() {
        pending?.resume(returning: stored)
        pending = nil
    }
}

private actor NavigationDelayedCatalog: BibleCatalogRepository {
    let storedBooks: [BibleBook]
    private var pending: CheckedContinuation<[Int], Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(books: [BibleBook]) { storedBooks = books }
    func books() async throws -> [BibleBook] { storedBooks }
    func chapters(in bookID: String) async throws -> [Int] {
        await withCheckedContinuation {
            pending = $0
            waiter?.resume()
            waiter = nil
        }
    }
    func verses(in bookID: String, chapter: Int) async throws -> [BibleVerse] { [] }
    func waitUntilStarted() async {
        guard pending == nil else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() {
        pending?.resume(returning: [2, 3])
        pending = nil
    }
}

/// Delays `chapters(in:)` for one book until `finish()`; other calls pass
/// through to the in-memory base.
private actor SteppingDelayedCatalog: BibleCatalogRepository, BibleRepository {
    let base: InMemoryBibleRepository
    let delayedBookID: String
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(base: InMemoryBibleRepository, delayedBookID: String) {
        self.base = base
        self.delayedBookID = delayedBookID
    }

    func books() async throws -> [BibleBook] { try await base.books() }

    func chapters(in bookID: String) async throws -> [Int] {
        if bookID == delayedBookID {
            await withCheckedContinuation {
                pending = $0
                waiter?.resume()
                waiter = nil
            }
        }
        return try await base.chapters(in: bookID)
    }

    func verses(in bookID: String, chapter: Int) async throws -> [BibleVerse] {
        try await base.verses(in: bookID, chapter: chapter)
    }

    func verse(at reference: BibleReference) async throws -> BibleVerse {
        try await base.verse(at: reference)
    }

    func waitUntilStarted() async {
        guard pending == nil else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func finish() {
        pending?.resume()
        pending = nil
    }
}
