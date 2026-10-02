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
    let aiEngine: AIEngineModel
    let chatModel: BibleChatModel
    let semanticSearch: SemanticSearchModel
    let catalogModel: BibleCatalogModel
    let textSearchModel: BibleTextSearchModel

    private enum SearchMode: String, CaseIterable, Identifiable {
        case reference = "Reference"
        case text = "Text"

        var id: Self { self }
    }

    @State private var navigation: BibleReaderNavigationModel
    @State private var searchText = ""
    @State private var textQuery = ""
    @State private var searchMode = SearchMode.reference
    /// Drill-down: the book list, or the chapter grid of the selected book.
    @State private var showsBookList = true
    @State private var bookFilter = ""
    /// A verse opened from the chat (citation or source); it is shown in
    /// the reader but not attached to the next question.
    @State private var openedFromChat: BibleReference?

    private typealias ChapterSelection = BibleReaderNavigationModel.ChapterSelection
    private var selectedBookID: String? { navigation.selectedBookID }
    private var selectedChapter: ChapterSelection? { navigation.selectedChapter }
    private var selectedReference: BibleReference? { navigation.selectedReference }
    private var activeReference: BibleReference? { navigation.activeReference }

    init(
        model: BibleReaderModel,
        aiEngine: AIEngineModel,
        chatModel: BibleChatModel,
        semanticSearch: SemanticSearchModel,
        catalogModel: BibleCatalogModel,
        searchModel: BibleReferenceSearchModel,
        textSearchModel: BibleTextSearchModel,
        readingPositionStore: ReadingPositionStore
    ) {
        self.model = model
        self.aiEngine = aiEngine
        self.chatModel = chatModel
        self.semanticSearch = semanticSearch
        self.catalogModel = catalogModel
        self.textSearchModel = textSearchModel
        _navigation = State(initialValue: BibleReaderNavigationModel(
            search: searchModel, catalog: catalogModel, store: readingPositionStore
        ))
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
            .safeAreaInset(edge: .top) { searchControls }
            .onChange(of: selectedBookID) { _, bookID in
                // Search, restoration and cross-book steps also change the
                // book; show its chapters whenever that happens.
                if bookID != nil { showsBookList = false }
            }
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
                // The reading column needs a floor: without one it was
                // squeezed to ~200 pt while the study panel took the rest.
                // The floor also applies to a previously saved layout.
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
                .navigationTitle(locationTitle)
        } detail: {
            BibleChatView(
                model: chatModel,
                engine: aiEngine,
                semanticSearch: semanticSearch,
                open: openFromChat
            )
            // One rule for every study-panel state, capped so spare width
            // goes to the reading column instead.
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .onDisappear {
            navigation.cancelSearch()
            textSearchModel.cancel()
        }
        .onChange(of: searchMode) { _, _ in
            navigation.cancelSearch()
            textSearchModel.cancel()
        }
        .onChange(of: activeReference) { _, reference in
            // A verse you choose attaches to the next chat question; a verse
            // opened from the chat only shows in the reader.
            guard let reference else { return }
            if reference == openedFromChat {
                openedFromChat = nil
                return
            }
            openedFromChat = nil
            let chapterVerses = loadedChapterVerses(for: reference)
            guard let verse = chapterVerses.first(where: { $0.reference == reference }) else { return }
            chatModel.attach(
                verse: verse,
                bookName: bookName(for: reference.bookID) ?? reference.bookID,
                chapterVerses: chapterVerses
            )
        }
    }
    
    @ViewBuilder
    private var sidebarContent: some View {
        if searchMode == .text {
            List {
                Section("Results") {
                    textSearchResultsContent
                }
            }
        } else if showsBookList || selectedBookID == nil {
            bookListContent
        } else {
            chapterGridContent
        }
    }

    private var bookListContent: some View {
        List {
            TextField("Filter books", text: $bookFilter)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("bookFilterField")

            switch catalogModel.state {
            case .idle, .loading:
                ProgressView("Loading books…")

            case let .loaded(books):
                let visible = filteredBooks(books)
                if visible.isEmpty {
                    Text(books.isEmpty ? "No books available" : "No books match")
                        .foregroundStyle(.secondary)
                }

                ForEach(BibleBook.Testament.allCases, id: \.self) { testament in
                    let group = visible.filter { $0.testament == testament }
                    if !group.isEmpty {
                        Section(testament == .old ? "Old Testament" : "New Testament") {
                            ForEach(group) { book in
                                bookRow(book)
                            }
                        }
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
    }

    private func bookRow(_ book: BibleBook) -> some View {
        Button {
            navigation.selectBook(book.bookID)
            showsBookList = false
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
        .accessibilityIdentifier("book-\(book.bookID)")
        .accessibilityAddTraits(
            selectedBookID == book.bookID ? .isSelected : []
        )
    }

    /// Case- and diacritic-insensitive match on the book name.
    private func filteredBooks(_ books: [BibleBook]) -> [BibleBook] {
        let filter = bookFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return books }
        return books.filter { $0.name.localizedStandardContains(filter) }
    }

    @ViewBuilder
    private var chapterGridContent: some View {
        if let selectedBookID {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            showsBookList = true
                        } label: {
                            Label("Books", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("backToBooksButton")

                        Spacer()

                        Text(bookName(for: selectedBookID) ?? selectedBookID)
                            .font(.headline)
                    }

                    switch catalogModel.chaptersState {
                    case let .loaded(bookID, chapters) where bookID == selectedBookID:
                        if chapters.isEmpty {
                            Text("No chapters available")
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 44), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(chapters, id: \.self) { chapter in
                                    chapterCell(chapter, in: selectedBookID)
                                }
                            }
                        }

                    case let .failed(bookID, _) where bookID == selectedBookID:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn’t load chapters")
                                .foregroundStyle(.secondary)

                            Button("Retry") {
                                Task {
                                    await catalogModel.loadChapters(in: selectedBookID)
                                }
                            }
                        }

                    default:
                        ProgressView("Loading chapters…")
                    }
                }
                .padding(12)
            }
        }
    }

    private func chapterCell(_ chapter: Int, in bookID: String) -> some View {
        let isSelected = selectedChapter == ChapterSelection(bookID: bookID, chapter: chapter)

        return Button {
            selectChapter(chapter, in: bookID)
        } label: {
            Text("\(chapter)")
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter \(chapter)")
        .accessibilityIdentifier("chapter-\(bookID)-\(chapter)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Breadcrumb for the reading pane, e.g. "John 3".
    private var locationTitle: String {
        guard let selectedChapter else { return "Bible" }
        let name = bookName(for: selectedChapter.bookID) ?? selectedChapter.bookID
        return "\(name) \(selectedChapter.chapter)"
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
                        title: locationTitle,
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
    private var chapterNavigationControls: some View {
        if selectedChapter != nil {
            HStack {
                Button {
                    Task { await navigation.goToPreviousChapter() }
                } label: {
                    Label("Previous Chapter", systemImage: "chevron.left")
                }
                .disabled(!navigation.canGoToPreviousChapter)
                .keyboardShortcut("[", modifiers: .command)
                .help("Previous chapter (⌘[)")

                Spacer()

                Button {
                    navigation.selectAdjacentVerse(-1)
                } label: {
                    Label("Previous Verse", systemImage: "chevron.up")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.upArrow, modifiers: .option)
                .help("Previous verse (⌥↑)")

                Button {
                    navigation.selectAdjacentVerse(1)
                } label: {
                    Label("Next Verse", systemImage: "chevron.down")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.downArrow, modifiers: .option)
                .help("Next verse (⌥↓)")

                Spacer()

                Button {
                    Task { await navigation.goToNextChapter() }
                } label: {
                    Label("Next Chapter", systemImage: "chevron.right")
                }
                .disabled(!navigation.canGoToNextChapter)
                .keyboardShortcut("]", modifiers: .command)
                .help("Next chapter (⌘])")
            }
            .buttonStyle(.bordered)
            .padding()
            .background(.bar)
        }
    }

    private func openFromChat(_ reference: BibleReference) {
        openedFromChat = reference == activeReference ? nil : reference
        navigation.open(reference)
    }

    private func selectChapter(_ chapter: Int, in bookID: String) {
        navigation.selectChapter(chapter, in: bookID)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Search type", selection: $searchMode) {
                ForEach(SearchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("searchModePicker")

            switch searchMode {
            case .reference:
                referenceSearchControls
            case .text:
                textSearchControls
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var referenceSearchControls: some View {
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

    @ViewBuilder
    private var textSearchControls: some View {
        HStack {
            TextField("Words or \"a phrase\"", text: $textQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search the Bible text")
                .accessibilityIdentifier("textSearchField")
                .onSubmit { submitTextSearch() }
                .onChange(of: textQuery) { _, _ in textSearchModel.cancel() }
            Button("Go", action: submitTextSearch)
                .accessibilityIdentifier("textSearchButton")
                .disabled(textQuery.allSatisfy(\.isWhitespace))
        }
        if case .loading = textSearchModel.state {
            HStack {
                ProgressView().controlSize(.small)
                Text("Searching…")
                Spacer()
                Button("Cancel") { textSearchModel.cancel() }
            }
        } else {
            Text("All words, any order. Use quotes for a phrase.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var textSearchResultsContent: some View {
        switch textSearchModel.state {
        case .idle:
            Text("Search the King James text above.")
                .foregroundStyle(.secondary)
        case .tooShort:
            Text("Enter at least two letters.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("textSearchStatus")
        case .loading:
            ProgressView("Searching…")
        case let .failed(_, message):
            Text(message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("textSearchStatus")
        case let .loaded(_, result):
            if result.verses.isEmpty {
                Text("No verses match.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("textSearchStatus")
            } else {
                Text(textSearchSummary(for: result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("textSearchStatus")
                ForEach(result.verses, id: \.reference) { verse in
                    Button {
                        navigation.open(verse)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(referenceLabel(for: verse.reference))
                                .font(.caption.bold())
                            Text(verse.text)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "textSearchResult-\(verse.reference.bookID)-\(verse.reference.chapter)-\(verse.reference.verse)"
                    )
                }
            }
        }
    }

    private func textSearchSummary(for result: BibleTextSearchResult) -> String {
        if result.isTruncated {
            return "Showing first \(result.verses.count) of \(result.totalCount) verses"
        }
        return result.totalCount == 1 ? "1 verse" : "\(result.totalCount) verses"
    }

    private func referenceLabel(for reference: BibleReference) -> String {
        let name = bookName(for: reference.bookID) ?? reference.bookID
        return "\(name) \(reference.chapter):\(reference.verse)"
    }

    private func bookName(for bookID: String) -> String? {
        guard case let .loaded(books) = catalogModel.state else { return nil }
        return books.first(where: { $0.bookID == bookID })?.name
    }

    /// The loaded chapter's verses, only if they belong to `reference`.
    private func loadedChapterVerses(for reference: BibleReference) -> [BibleVerse] {
        guard case let .loaded(bookID, chapter, verses) = catalogModel.versesState,
              bookID == reference.bookID, chapter == reference.chapter
        else { return [] }
        return verses
    }

    private func submitSearch() {
        guard !searchText.allSatisfy(\.isWhitespace) else { return }
        navigation.search(searchText)
    }

    private func submitTextSearch() {
        guard !textQuery.allSatisfy(\.isWhitespace) else { return }
        textSearchModel.submit(textQuery)
    }
}
