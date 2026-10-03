//
//  BibleReaderView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import SwiftUI
import BibleDomain

struct BibleReaderView: View {
    let aiEngine: AIEngineModel
    let chatModel: BibleChatModel
    let semanticSearch: SemanticSearchModel
    let catalogModel: BibleCatalogModel
    let textSearchModel: BibleTextSearchModel
    let library: BibleLibraryModel
    let compare: BibleCompareModel
    let version: BibleVersion
    let switchVersion: (String) -> Void
    let appNavigation: AppNavigation

    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    enum SearchMode: CaseIterable, Identifiable {
        case reference
        case text

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .reference: "Reference"
            case .text: "Text"
            }
        }
    }

    @State var navigation: BibleReaderNavigationModel
    @State var searchText = ""
    @State var textQuery = ""
    @State var searchMode = SearchMode.reference
    /// Drill-down: the book list, or the chapter grid of the selected book.
    @State private var showsBookList = true
    @State private var bookFilter = ""
    /// The selection revision produced by opening a verse from the chat
    /// (citation or source); that selection is shown but not attached.
    @State var chatOpenRevision: Int?
    @State var isShowingSettings = false

    /// Changes on every verse selection, including choosing the same verse
    /// again, and when the selected verse's chapter finishes loading.
    private struct VerseSelection: Equatable {
        let revision: Int
        let reference: BibleReference?
    }

    typealias ChapterSelection = BibleReaderNavigationModel.ChapterSelection
    var selectedBookID: String? { navigation.selectedBookID }
    var selectedChapter: ChapterSelection? { navigation.selectedChapter }
    var activeReference: BibleReference? { navigation.activeReference }

    init(
        aiEngine: AIEngineModel,
        chatModel: BibleChatModel,
        semanticSearch: SemanticSearchModel,
        catalogModel: BibleCatalogModel,
        searchModel: BibleReferenceSearchModel,
        textSearchModel: BibleTextSearchModel,
        readingPositionStore: ReadingPositionStore,
        library: BibleLibraryModel,
        compare: BibleCompareModel,
        version: BibleVersion,
        switchVersion: @escaping (String) -> Void,
        appNavigation: AppNavigation
    ) {
        self.appNavigation = appNavigation
        self.library = library
        self.compare = compare
        self.version = version
        self.switchVersion = switchVersion
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
        layout
            .task {
                await catalogModel.loadBooks()
                await navigation.restoreReadingPosition()
                // A book chosen while restoring stays where the user put it.
                if selectedChapter != nil || selectedBookID == nil {
                    appNavigation.positionRestored(hasChapter: selectedChapter != nil)
                }
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
            .onDisappear {
                navigation.cancelSearch()
                textSearchModel.cancel()
            }
            .onChange(of: searchMode) { _, _ in
                navigation.cancelSearch()
                textSearchModel.cancel()
            }
            .onChange(of: VerseSelection(revision: navigation.selectionRevision, reference: activeReference)) { _, selection in
                // A verse you choose attaches to the next chat question (again
                // after ✕ when chosen again); a verse opened from the chat only
                // shows in the reader.
                guard let reference = selection.reference, selection.revision != chatOpenRevision else { return }
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
    private var layout: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            phoneLayout
        } else {
            padLayout
        }
        #else
        splitLayout
        #endif
    }

    /// Mac and visionOS: books, reader and chat side by side.
    private var splitLayout: some View {
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
        } content: {
            readerContent
                .safeAreaInset(edge: .bottom) {
                    ChapterNavigationBar(navigation: navigation)
                }
                // The reading column needs a floor: without one it was
                // squeezed to ~200 pt while the study panel took the rest.
                // The floor also applies to a previously saved layout.
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
                .navigationTitle(locationTitle)
                .toolbar {
                    ToolbarItem {
                        BibleVersionMenu(library: library, current: version, switchVersion: switchVersion)
                    }
                    ToolbarItem {
                        BibleCompareMenu(model: compare, library: library, primary: version)
                    }
                }
        } detail: {
            chatView()
            // One rule for every study-panel state, capped so spare width
            // goes to the reading column instead.
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    var sidebarContent: some View {
        if searchMode == .text {
            List {
                Section("Results") {
                    TextSearchResultRows(model: textSearchModel, catalogModel: catalogModel) { verse in
                        navigation.open(verse)
                    }
                }
            }
        } else if showsBookList || selectedBookID == nil {
            bookList { bookID in
                navigation.selectBook(bookID)
                showsBookList = false
            }
        } else {
            chapterGridContent
        }
    }

    func bookList(select: @escaping (String) -> Void) -> some View {
        BookListView(
            catalogModel: catalogModel,
            selectedBookID: selectedBookID,
            filter: $bookFilter,
            select: select
        )
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

                    chapterGrid(for: selectedBookID) { chapter in
                        navigation.selectChapter(chapter, in: selectedBookID)
                    }
                }
                .padding(12)
            }
        }
    }

    func chapterGrid(for bookID: String, select: @escaping (Int) -> Void) -> some View {
        ChapterGridView(
            catalogModel: catalogModel,
            bookID: bookID,
            selectedChapter: selectedChapter,
            select: select
        )
    }

    /// Breadcrumb for the reading pane, e.g. "John 3".
    var locationTitle: String {
        guard let selectedChapter else { return String(localized: "Bible") }
        let name = bookName(for: selectedChapter.bookID) ?? selectedChapter.bookID
        return "\(name) \(selectedChapter.chapter)"
    }

    var readerContent: some View {
        ChapterReaderContent(
            catalogModel: catalogModel,
            navigation: navigation,
            compare: compare,
            library: library,
            version: version,
            title: locationTitle
        )
    }

    func chatView(showsHeader: Bool = true) -> some View {
        BibleChatView(
            model: chatModel,
            engine: aiEngine,
            semanticSearch: semanticSearch,
            showsHeader: showsHeader,
            open: openFromChat
        )
    }

    func openFromChat(_ reference: BibleReference) {
        navigation.open(reference)
        chatOpenRevision = navigation.selectionRevision
        appNavigation.showReader()
    }

    var searchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Search type", selection: $searchMode) {
                ForEach(SearchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
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

    func bookName(for bookID: String) -> String? {
        catalogModel.bookName(for: bookID)
    }

    /// The loaded chapter's verses, only if they belong to `reference`.
    func loadedChapterVerses(for reference: BibleReference) -> [BibleVerse] {
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
