//
//  BibleReaderView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import SwiftUI
import BibleDomain

struct BibleReaderView: View {
    let model: BibleReaderModel
    let studyAssistantModel: StudyAssistantModel
    let catalogModel: BibleCatalogModel

    @State private var selectedBookID: String?
    @State private var selectedChapter: ChapterSelection?
    @State private var selectedReference: BibleReference?

    private struct ChapterSelection: Hashable {
        let bookID: String
        let chapter: Int
    }
    
    private var activeReference: BibleReference? {
        guard let selectedReference,
              let selectedChapter,
              selectedChapter.bookID == selectedBookID,
              selectedReference.bookID == selectedChapter.bookID,
              selectedReference.chapter == selectedChapter.chapter,
              case let .loaded(bookID, chapter, verses) =
                catalogModel.versesState,
              bookID == selectedChapter.bookID,
              chapter == selectedChapter.chapter,
              verses.contains(where: {
                  $0.reference == selectedReference
              })
        else {
            return nil
        }

        return selectedReference
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedReference) {
                Section("Books") {
                    bookCatalogContent
                }

                Section("Chapters") {
                    chapterCatalogContent
                }

                Section("Verses") {
                    verseCatalogContent
                }
            }
            .navigationTitle("Bible")
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 240,
                max: 320
            )
            .task {
                await catalogModel.loadBooks()
            }
            .task(id: selectedBookID) {
                guard let selectedBookID else {
                    return
                }

                await catalogModel.loadChapters(in: selectedBookID)
            }
            .task(id: selectedChapter) {
                guard let selectedChapter else {
                    return
                }

                await catalogModel.loadVerses(
                    in: selectedChapter.bookID,
                    chapter: selectedChapter.chapter
                )
            }
        } content: {
            if let reference = activeReference {
                verseContent(for: reference)
                    .task(id: reference) {
                        await model.load(reference: reference)
                    }
            } else {
                ContentUnavailableView(
                    "Select a Verse",
                    systemImage: "book.closed",
                    description: Text(
                        "Choose a book, chapter, and verse."
                    )
                )
            }
        } detail: {
            if let reference = activeReference,
               case let .loaded(verse) = model.state,
               verse.reference == reference {
                StudyAssistantView(
                    model: studyAssistantModel,
                    verse: verse
                )
                .id(verse.reference)
                .navigationSplitViewColumnWidth(
                    min: 320,
                    ideal: 400
                )
            } else {
                ContentUnavailableView(
                    "AI Study Assistant",
                    systemImage: "sparkles",
                    description: Text(
                        "Select a verse to begin studying."
                    )
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func verseContent(
        for reference: BibleReference
    ) -> some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading verse…")

        case let .loaded(verse):
            if verse.reference == reference {
                VStack(alignment: .leading, spacing: 16) {
                    Text(
                        "\(verse.reference.bookID) " +
                        "\(verse.reference.chapter):" +
                        "\(verse.reference.verse)"
                    )
                    .font(.title2.bold())

                    Text(verse.text)
                        .font(.title3)
                        .textSelection(.enabled)
                }
                .frame(
                    maxWidth: 600,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .padding(32)
            } else {
                ProgressView("Loading verse…")
            }

        case let .failed(message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Couldn’t load the verse")
                    .font(.headline)

                Text(message)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task {
                        await model.load(reference: reference)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var bookCatalogContent: some View {
        switch catalogModel.state {
        case .idle, .loading:
            ProgressView("Loading books…")

        case let .loaded(books):
            if books.isEmpty {
                Text("No books available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(books) { book in
                    Button {
                        selectedReference = nil
                        selectedChapter = nil
                        selectedBookID = book.bookID
                    } label: {
                        HStack {
                            Label(book.name, systemImage: "book.closed")

                            Spacer()

                            if selectedBookID == book.bookID {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selectedBookID == book.bookID ? .isSelected : []
                    )
                }
            }

        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t load books")
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task {
                        await catalogModel.loadBooks()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var chapterCatalogContent: some View {
        if let selectedBookID {
            switch catalogModel.chaptersState {
            case let .loaded(bookID, chapters)
                where bookID == selectedBookID:
                if chapters.isEmpty {
                    Text("No chapters available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chapters, id: \.self) { chapter in
                        let selection = ChapterSelection(
                            bookID: selectedBookID,
                            chapter: chapter
                        )

                        Button {
                            selectedReference = nil
                            selectedChapter = selection
                        } label: {
                            HStack {
                                Text("Chapter \(chapter)")

                                Spacer()

                                if selectedChapter == selection {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedChapter == selection ? .isSelected : []
                        )
                    }
                }

            case let .failed(bookID, _)
                where bookID == selectedBookID:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t load chapters")
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task {
                            await catalogModel.loadChapters(
                                in: selectedBookID
                            )
                        }
                    }
                }

            default:
                ProgressView("Loading chapters…")
            }
        } else {
            Text("Select a book")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var verseCatalogContent: some View {
        if let selectedChapter {
            switch catalogModel.versesState {
            case let .loaded(bookID, chapter, verses)
                where bookID == selectedChapter.bookID
                    && chapter == selectedChapter.chapter:
                if verses.isEmpty {
                    Text("No verses available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(verses, id: \.reference) { verse in
                        Text("Verse \(verse.reference.verse)")
                            .tag(verse.reference)
                    }
                }

            case let .failed(bookID, chapter, _)
                where bookID == selectedChapter.bookID
                    && chapter == selectedChapter.chapter:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t load verses")
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task {
                            await catalogModel.loadVerses(
                                in: selectedChapter.bookID,
                                chapter: selectedChapter.chapter
                            )
                        }
                    }
                }

            default:
                ProgressView("Loading verses…")
            }
        } else {
            Text("Select a chapter")
                .foregroundStyle(.secondary)
        }
    }
}
