import BibleDomain
import Observation
import OSLog

/// One selection owner for browsing, search, and restoration.
@MainActor
@Observable
final class BibleReaderNavigationModel {
    struct ChapterSelection: Hashable {
        let bookID: String
        let chapter: Int
    }

    private(set) var selectedBookID: String?
    private(set) var selectedChapter: ChapterSelection?
    private(set) var selectedReference: BibleReference?
    private(set) var selectionRevision = 0
    let searchModel: BibleReferenceSearchModel

    @ObservationIgnored private let catalog: BibleCatalogModel
    @ObservationIgnored private let store: ReadingPositionStore
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var hasAttemptedPositionRestore = false

    private static let logger = Logger(subsystem: "OpenBibleAI", category: "ReadingPosition")

    init(search: BibleReferenceSearchModel, catalog: BibleCatalogModel, store: ReadingPositionStore) {
        searchModel = search
        self.catalog = catalog
        self.store = store
    }

    var activeReference: BibleReference? {
        guard let selectedReference, let selectedChapter,
              selectedChapter.bookID == selectedBookID,
              selectedReference.bookID == selectedChapter.bookID,
              selectedReference.chapter == selectedChapter.chapter,
              case let .loaded(bookID, chapter, verses) = catalog.versesState,
              bookID == selectedChapter.bookID, chapter == selectedChapter.chapter,
              verses.contains(where: { $0.reference == selectedReference })
        else { return nil }
        return selectedReference
    }

    func selectBook(_ bookID: String) {
        cancelSearch()
        selectedReference = nil
        selectedChapter = nil
        selectedBookID = bookID
    }

    func selectChapter(_ chapter: Int, in bookID: String) {
        cancelSearch()
        selectedBookID = bookID
        selectedChapter = ChapterSelection(bookID: bookID, chapter: chapter)
        selectedReference = nil
        savePosition()
    }

    func selectVerse(_ reference: BibleReference) {
        guard reference.bookID == selectedChapter?.bookID,
              reference.chapter == selectedChapter?.chapter else { return }
        cancelSearch()
        selectedReference = reference
        selectionRevision += 1
    }

    func deselectVerse() {
        // A List can clear its binding while replacing chapter rows. Only
        // accept deselection when the selected verse belongs to loaded rows.
        guard activeReference != nil else { return }
        cancelSearch()
        selectedReference = nil
    }

    /// Also used when editing the query or leaving the reader. Invalidation
    /// protects selection even if a dependency ignores task cancellation.
    func cancelSearch() {
        generation += 1
        hasAttemptedPositionRestore = true
        searchTask?.cancel()
        searchTask = nil
        searchModel.reset()
    }

    @discardableResult
    func search(_ query: String) -> Task<Void, Never> {
        cancelSearch()
        let requestGeneration = generation
        let task = Task {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            defer {
                if requestGeneration == generation { searchTask = nil }
            }
            await searchModel.search(query)
            guard !Task.isCancelled, requestGeneration == generation,
                  case let .loaded(loadedQuery, verse) = searchModel.state,
                  loadedQuery == query else { return }

            apply(verse.reference)
        }
        searchTask = task
        return task
    }

    /// Opens a verse chosen from text-search results through the same
    /// selection and persistence path as an exact-reference search.
    func open(_ verse: BibleVerse) {
        cancelSearch()
        apply(verse.reference)
    }

    private func apply(_ reference: BibleReference) {
        selectedBookID = reference.bookID
        selectedChapter = ChapterSelection(bookID: reference.bookID, chapter: reference.chapter)
        selectedReference = reference
        selectionRevision += 1
        savePosition()
    }

    func restoreReadingPosition() async {
        guard !hasAttemptedPositionRestore, selectedBookID == nil,
              selectedChapter == nil, case .loaded = catalog.state else { return }
        let restoreGeneration = generation
        do {
            try Task.checkCancellation()
            guard let position = try store.load() else {
                hasAttemptedPositionRestore = true
                return
            }
            let available = try await catalog.isAvailable(position)
            try Task.checkCancellation()
            guard restoreGeneration == generation, !hasAttemptedPositionRestore,
                  selectedBookID == nil, selectedChapter == nil else { return }
            hasAttemptedPositionRestore = true
            guard available else { return }
            selectedBookID = position.bookID
            selectedChapter = ChapterSelection(bookID: position.bookID, chapter: position.chapter)
        } catch is CancellationError {
            return
        } catch {
            guard restoreGeneration == generation else { return }
            hasAttemptedPositionRestore = true
            Self.logger.notice("Could not restore reading position: \(String(describing: error))")
        }
    }

    private func savePosition() {
        guard let selectedChapter else { return }
        do {
            try store.save(ReadingPosition(bookID: selectedChapter.bookID, chapter: selectedChapter.chapter))
        } catch {
            Self.logger.error("Could not save reading position: \(String(describing: error))")
        }
    }
}
