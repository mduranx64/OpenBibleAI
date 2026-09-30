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
            chapterReadingContent
                .safeAreaInset(edge: .bottom) {
                    chapterNavigationControls
                }
        } detail: {
            if let reference = activeReference {
                studyContent(for: reference)
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
        .task(id: activeReference) {
            guard let reference = activeReference else {
                return
            }

            await model.load(reference: reference)
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
                            selectChapter(
                                chapter,
                                in: selectedBookID
                            )
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
    
    @ViewBuilder
    private var chapterReadingContent: some View {
        if let selectedChapter {
            switch catalogModel.versesState {
            case let .loaded(bookID, chapter, verses)
                where bookID == selectedChapter.bookID
                    && chapter == selectedChapter.chapter:
                if verses.isEmpty {
                    ContentUnavailableView(
                        "No Verses Available",
                        systemImage: "book.closed"
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(
                                alignment: .leading,
                                spacing: 12
                            ) {
                                Text("Chapter \(chapter)")
                                    .font(.title.bold())
                                    .padding(.bottom, 8)

                                ForEach(verses, id: \.reference) { verse in
                                    Button {
                                        selectedReference = verse.reference
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(verse.reference.verse)")
                                                .font(.caption.bold())
                                                .foregroundStyle(.secondary)
                                                .frame(
                                                    minWidth: 24,
                                                    alignment: .trailing
                                                )

                                            Text(verse.text)
                                                .font(.title3)
                                                .multilineTextAlignment(.leading)
                                                .frame(
                                                    maxWidth: .infinity,
                                                    alignment: .leading
                                                )
                                        }
                                        .padding(12)
                                        .background(
                                            selectedReference == verse.reference
                                                ? Color.accentColor.opacity(0.12)
                                                : Color.clear,
                                            in: RoundedRectangle(
                                                cornerRadius: 8
                                            )
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(
                                        selectedReference == verse.reference
                                            ? .isSelected
                                            : []
                                    )
                                    .id(verse.reference)
                                }
                            }
                            .frame(maxWidth: 720, alignment: .leading)
                            .padding(24)
                            .frame(maxWidth: .infinity)
                        }
                        .onChange(
                            of: selectedReference,
                            initial: true
                        ) { _, reference in
                            guard let reference,
                                  verses.contains(where: {
                                      $0.reference == reference
                                  })
                            else {
                                return
                            }

                            proxy.scrollTo(reference, anchor: .center)
                        }
                    }
                }

            case let .failed(bookID, chapter, _)
                where bookID == selectedChapter.bookID
                    && chapter == selectedChapter.chapter:
                VStack(spacing: 12) {
                    Text("Couldn’t load this chapter")
                        .font(.headline)

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
                ProgressView("Loading chapter…")
            }
        } else {
            ContentUnavailableView(
                "Select a Chapter",
                systemImage: "book.closed",
                description: Text(
                    "Choose a book and chapter to begin reading."
                )
            )
        }
    }
    
    @ViewBuilder
    private func studyContent(
        for reference: BibleReference
    ) -> some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading selected verse…")

        case let .loaded(verse):
            if verse.reference == reference {
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
                ProgressView("Loading selected verse…")
            }

        case .failed:
            VStack(spacing: 12) {
                Text("Couldn’t load the selected verse")
                    .font(.headline)

                Button("Retry") {
                    Task {
                        await model.load(reference: reference)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var chapterNavigationControls: some View {
        if let selectedChapter {
            let previous = catalogModel.previousChapter(
                in: selectedChapter.bookID,
                before: selectedChapter.chapter
            )

            let next = catalogModel.nextChapter(
                in: selectedChapter.bookID,
                after: selectedChapter.chapter
            )

            HStack {
                Button {
                    if let previous {
                        selectChapter(
                            previous,
                            in: selectedChapter.bookID
                        )
                    }
                } label: {
                    Label(
                        "Previous Chapter",
                        systemImage: "chevron.left"
                    )
                }
                .disabled(previous == nil)

                Spacer()

                Button {
                    if let next {
                        selectChapter(
                            next,
                            in: selectedChapter.bookID
                        )
                    }
                } label: {
                    Label(
                        "Next Chapter",
                        systemImage: "chevron.right"
                    )
                }
                .disabled(next == nil)
            }
            .buttonStyle(.bordered)
            .padding()
            .background(.bar)
        }
    }

    private func selectChapter(
        _ chapter: Int,
        in bookID: String
    ) {
        selectedReference = nil

        selectedChapter = ChapterSelection(
            bookID: bookID,
            chapter: chapter
        )
    }
}
