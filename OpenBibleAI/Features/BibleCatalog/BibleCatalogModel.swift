//
//  BibleCatalogModel.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import Observation
import BibleDomain

@MainActor
@Observable
final class BibleCatalogModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([BibleBook])
        case failed(String)
    }
    
    enum ChaptersState: Equatable {
        case idle
        case loading(bookID: String)
        case loaded(bookID: String, chapters: [Int])
        case failed(bookID: String, message: String)
    }
    
    enum VersesState: Equatable {
        case idle
        case loading(bookID: String, chapter: Int)
        case loaded(
            bookID: String,
            chapter: Int,
            verses: [BibleVerse]
        )
        case failed(
            bookID: String,
            chapter: Int,
            message: String
        )
    }

    private(set) var versesState: VersesState = .idle

    @ObservationIgnored
    private var versesLoadGeneration = 0

    private(set) var chaptersState: ChaptersState = .idle

    @ObservationIgnored
    private var chaptersLoadGeneration = 0

    private(set) var state: State = .idle

    @ObservationIgnored
    private let repository: any BibleCatalogRepository

    init(repository: any BibleCatalogRepository) {
        self.repository = repository
    }

    func loadBooks() async {
        guard state != .loading else {
            return
        }

        let previousState = state
        state = .loading

        do {
            let books = try await repository.books()

            try Task.checkCancellation()

            state = .loaded(books)
        } catch is CancellationError {
            state = previousState
        } catch {
            state = .failed(String(describing: error))
        }
    }
    
    func loadChapters(in bookID: String) async {
        chaptersLoadGeneration += 1
        let currentGeneration = chaptersLoadGeneration

        chaptersState = .loading(bookID: bookID)

        do {
            let chapters = try await repository.chapters(in: bookID)

            try Task.checkCancellation()

            guard currentGeneration == chaptersLoadGeneration else {
                return
            }

            chaptersState = .loaded(
                bookID: bookID,
                chapters: chapters
            )
        } catch is CancellationError {
            guard currentGeneration == chaptersLoadGeneration else {
                return
            }

            chaptersState = .idle
        } catch {
            guard currentGeneration == chaptersLoadGeneration else {
                return
            }

            chaptersState = .failed(
                bookID: bookID,
                message: String(describing: error)
            )
        }
    }
    
    func loadVerses(in bookID: String, chapter: Int) async {
        versesLoadGeneration += 1
        let currentGeneration = versesLoadGeneration

        versesState = .loading(
            bookID: bookID,
            chapter: chapter
        )

        do {
            let verses = try await repository.verses(
                in: bookID,
                chapter: chapter
            )

            try Task.checkCancellation()

            guard currentGeneration == versesLoadGeneration else {
                return
            }

            versesState = .loaded(
                bookID: bookID,
                chapter: chapter,
                verses: verses
            )
        } catch is CancellationError {
            guard currentGeneration == versesLoadGeneration else {
                return
            }

            versesState = .idle
        } catch {
            guard currentGeneration == versesLoadGeneration else {
                return
            }

            versesState = .failed(
                bookID: bookID,
                chapter: chapter,
                message: String(describing: error)
            )
        }
    }
    
    func previousChapter(
        in bookID: String,
        before chapter: Int
    ) -> Int? {
        guard case let .loaded(loadedBookID, chapters) = chaptersState,
              loadedBookID == bookID,
              let index = chapters.firstIndex(of: chapter),
              index > chapters.startIndex
        else {
            return nil
        }

        return chapters[chapters.index(before: index)]
    }

    func nextChapter(
        in bookID: String,
        after chapter: Int
    ) -> Int? {
        guard case let .loaded(loadedBookID, chapters) = chaptersState,
              loadedBookID == bookID,
              let index = chapters.firstIndex(of: chapter)
        else {
            return nil
        }

        let nextIndex = chapters.index(after: index)

        guard nextIndex < chapters.endIndex else {
            return nil
        }

        return chapters[nextIndex]
    }

    /// Chapter numbers for any book, without changing the published
    /// chapter-list state (used to step across book boundaries).
    func chapterNumbers(in bookID: String) async throws -> [Int] {
        try Task.checkCancellation()
        let chapters = try await repository.chapters(in: bookID)
        try Task.checkCancellation()
        return chapters
    }

    func isAvailable(
        _ position: ReadingPosition
    ) async throws -> Bool {
        try Task.checkCancellation()

        let books = try await repository.books()

        try Task.checkCancellation()

        guard books.contains(where: {
            $0.bookID == position.bookID
        }) else {
            return false
        }

        let chapters = try await repository.chapters(
            in: position.bookID
        )

        try Task.checkCancellation()

        return chapters.contains(position.chapter)
    }
}
