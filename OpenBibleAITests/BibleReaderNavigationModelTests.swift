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
