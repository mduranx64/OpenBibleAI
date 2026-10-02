import BibleDomain
import Foundation
import Observation

@MainActor
@Observable
final class BibleReferenceSearchModel {
    enum State: Equatable {
        case idle
        case loading(query: String)
        case loaded(query: String, verse: BibleVerse)
        case failed(query: String, message: String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let catalog: any BibleCatalogRepository
    @ObservationIgnored private let verses: any BibleRepository
    @ObservationIgnored private var generation = 0

    init(catalog: any BibleCatalogRepository, verses: any BibleRepository) {
        self.catalog = catalog
        self.verses = verses
    }

    /// The caller owns the task. This method publishes lookup state only;
    /// it never changes reader selection or the saved reading position.
    func search(_ query: String) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let requestGeneration = generation
        state = .loading(query: query)

        do {
            let books = try await catalog.books()
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }

            let reference = try BibleReferenceParser.parse(query, books: books)
            let verse = try await verses.verse(at: reference)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }

            guard verse.reference == reference else {
                state = .failed(
                    query: query,
                    message: String(localized: "The repository returned a different verse. Please try again.")
                )
                return
            }
            state = .loaded(query: query, verse: verse)
        } catch {
            guard requestGeneration == generation else { return }
            if Task.isCancelled || error is CancellationError {
                state = .idle
            } else {
                state = .failed(query: query, message: message(for: error))
            }
        }
    }

    /// Invalidates pending results immediately. The caller should also cancel
    /// its task when leaving search; invalidation cannot stop repository work.
    func reset() {
        generation += 1
        state = .idle
    }

    private func message(for error: any Error) -> String {
        switch error {
        case BibleReferenceParser.ParseError.invalidSyntax:
            return String(localized: "Enter a full book name, chapter, and verse, such as John 3:16.")
        case let BibleReferenceParser.ParseError.unknownBook(name):
            return String(localized: "No book named “\(name)” was found. Use its full catalog name.")
        case let BibleReferenceParser.ParseError.ambiguousBook(name):
            return String(localized: "More than one catalog book matches “\(name)”.")
        case BibleReference.ValidationError.invalidChapter:
            return String(localized: "Chapter numbers must be greater than zero.")
        case BibleReference.ValidationError.invalidVerse:
            return String(localized: "Verse numbers must be greater than zero.")
        case InMemoryBibleRepository.LookupError.verseNotFound:
            return String(localized: "This verse is not available in the loaded Bible.")
        default:
            return String(localized: "Could not look up this reference. Please try again. \(String(describing: error))")
        }
    }
}
