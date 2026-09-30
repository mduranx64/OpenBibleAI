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

    @State private var navigation: BibleReaderNavigationModel
    @State private var searchText = ""

    private typealias ChapterSelection = BibleReaderNavigationModel.ChapterSelection
    private var selectedBookID: String? { navigation.selectedBookID }
    private var selectedChapter: ChapterSelection? { navigation.selectedChapter }
    private var selectedReference: BibleReference? { navigation.selectedReference }
    private var activeReference: BibleReference? { navigation.activeReference }

    init(
        model: BibleReaderModel,
        studyAssistantModel: StudyAssistantModel,
        catalogModel: BibleCatalogModel,
        searchModel: BibleReferenceSearchModel,
        readingPositionStore: ReadingPositionStore
    ) {
        self.model = model
        self.studyAssistantModel = studyAssistantModel
        self.catalogModel = catalogModel
        _navigation = State(initialValue: BibleReaderNavigationModel(
            search: searchModel, catalog: catalogModel, store: readingPositionStore
        ))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { selectedReference },
                set: { reference in
                    if let reference {
                        navigation.selectVerse(reference)
                    } else {
                        navigation.deselectVerse()
                    }
                }
            )) {
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
            .safeAreaInset(edge: .top) { searchControls }
            .navigationTitle("Bible")
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 240,
                max: 320
            )
            .task {
                await catalogModel.loadBooks()
                await navigation.restoreReadingPosition()
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
        .onDisappear { navigation.cancelSearch() }
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
                        navigation.selectBook(book.bookID)
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
                    BibleChapterReadingView(
                        chapter: chapter,
                        verses: verses,
                        selectedReference: selectedReference,
                        selectionRevision: navigation.selectionRevision,
                        selectVerse: navigation.selectVerse
                    )
                    .id(selectedChapter)
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

    private func selectChapter(_ chapter: Int, in bookID: String) {
        navigation.selectChapter(chapter, in: bookID)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("John 3:16", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bible reference")
                    .accessibilityIdentifier("referenceSearchField")
                    .onSubmit { submitSearch() }
                    .onChange(of: searchText) { _, _ in navigation.cancelSearch() }
                Button("Go", action: submitSearch)
                    .accessibilityIdentifier("referenceSearchButton")
                    .disabled(searchText.allSatisfy(\.isWhitespace))
            }
            switch navigation.searchModel.state {
            case .loading:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Finding verse…")
                    Spacer()
                    Button("Cancel") { navigation.cancelSearch() }
                }
            case let .failed(_, message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("referenceSearchError")
            default:
                Text("Full book name, chapter:verse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func submitSearch() {
        guard !searchText.allSatisfy(\.isWhitespace) else { return }
        navigation.search(searchText)
    }
}
