//
//  BibleReaderComponents.swift
//  OpenBibleAI
//
//  Pieces of the reader shared by the Mac split view, the iPhone tabs and
//  the iPad split view.
//

import BibleDomain
import SwiftUI

extension BibleCatalogModel {
    func bookName(for bookID: String) -> String? {
        guard case let .loaded(books) = state else { return nil }
        return books.first(where: { $0.bookID == bookID })?.name
    }

    /// Loaded books whose name begins with the typed reference ("jo" → John).
    func bookSuggestions(for input: String) -> [BibleBook] {
        guard case let .loaded(books) = state else { return [] }
        return BibleBookSuggestions.matching(input, in: books)
    }

    /// e.g. "John 3:16".
    func referenceLabel(for reference: BibleReference) -> String {
        let name = bookName(for: reference.bookID) ?? reference.bookID
        return "\(name) \(reference.chapter):\(reference.verse)"
    }
}

/// The books by testament, filtered by name.
struct BookListView: View {
    let catalogModel: BibleCatalogModel
    let selectedBookID: String?
    @Binding var filter: String
    let select: (String) -> Void

    var body: some View {
        List {
            TextField("Filter books", text: $filter)
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
            select(book.bookID)
        } label: {
            HStack {
                Label(book.name, systemImage: "book.closed")

                Spacer()

                if selectedBookID == book.bookID {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                #if os(iOS)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                #endif
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
        let filter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return books }
        return books.filter { $0.name.localizedStandardContains(filter) }
    }
}

/// The chapters of one book as a grid of numbers.
struct ChapterGridView: View {
    typealias ChapterSelection = BibleReaderNavigationModel.ChapterSelection

    let catalogModel: BibleCatalogModel
    let bookID: String
    let selectedChapter: ChapterSelection?
    let select: (Int) -> Void

    #if os(iOS)
    private static let cellMinimum: CGFloat = 52
    private static let cellHeight: CGFloat = 44
    #else
    private static let cellMinimum: CGFloat = 44
    private static let cellHeight: CGFloat = 32
    #endif

    var body: some View {
        switch catalogModel.chaptersState {
        case let .loaded(loadedBookID, chapters) where loadedBookID == bookID:
            if chapters.isEmpty {
                Text("No chapters available")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cellMinimum), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(chapters, id: \.self) { chapter in
                        chapterCell(chapter)
                    }
                }
            }

        case let .failed(loadedBookID, _) where loadedBookID == bookID:
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t load chapters")
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task {
                        await catalogModel.loadChapters(in: bookID)
                    }
                }
            }

        default:
            ProgressView("Loading chapters…")
        }
    }

    private func chapterCell(_ chapter: Int) -> some View {
        let isSelected = selectedChapter == ChapterSelection(bookID: bookID, chapter: chapter)

        return Button {
            select(chapter)
        } label: {
            Text("\(chapter)")
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: Self.cellHeight)
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
}

/// The selected chapter: its verses, the comparison, or a loading, empty or
/// failed state.
struct ChapterReaderContent: View {
    let catalogModel: BibleCatalogModel
    let navigation: BibleReaderNavigationModel
    let compare: BibleCompareModel
    let library: BibleLibraryModel
    let version: BibleVersion
    let title: String

    var body: some View {
        if let selectedChapter = navigation.selectedChapter {
            switch catalogModel.versesState {
            case let .loaded(bookID, chapter, verses)
                where bookID == selectedChapter.bookID
                    && chapter == selectedChapter.chapter:
                if verses.isEmpty {
                    ContentUnavailableView(
                        "No Verses Available",
                        systemImage: "book.closed"
                    )
                } else if compare.isComparing(primaryVersionID: version.id) {
                    BibleCompareView(
                        model: compare,
                        library: library,
                        primary: version,
                        title: title,
                        bookID: bookID,
                        chapter: chapter,
                        verses: verses,
                        selectedReference: navigation.selectedReference,
                        selectionRevision: navigation.selectionRevision,
                        selectVerse: navigation.selectVerse
                    )
                    .id(selectedChapter)
                } else {
                    BibleChapterReadingView(
                        title: title,
                        verses: verses,
                        selectedReference: navigation.selectedReference,
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
}

/// Previous/Next chapter and verse. The compact form (iPhone) shows icons
/// with the same accessibility labels.
struct ChapterNavigationBar: View {
    let navigation: BibleReaderNavigationModel
    var compact = false

    var body: some View {
        if navigation.selectedChapter != nil {
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
            .labelStyle(ChapterBarLabelStyle(compact: compact))
            .buttonStyle(.bordered)
            .padding(compact ? 10 : 16)
            .background(.bar)
        }
    }
}

/// Titles on wide layouts; icons only on iPhone, where four titled buttons
/// don't fit. Labels set to icon-only above stay icon-only.
private struct ChapterBarLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            // Icon only, keeping the title for VoiceOver.
            Label(configuration)
                .labelStyle(.iconOnly)
                .frame(minWidth: 28, minHeight: 28)
        } else {
            Label(configuration)
        }
    }
}

/// Text-search results, or the search status when there are none.
struct TextSearchResultRows: View {
    let model: BibleTextSearchModel
    let catalogModel: BibleCatalogModel
    let open: (BibleVerse) -> Void

    var body: some View {
        switch model.state {
        case .idle:
            Text("Search the Bible text above.")
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
                Text(summary(for: result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("textSearchStatus")
                ForEach(result.verses, id: \.reference) { verse in
                    Button {
                        open(verse)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(catalogModel.referenceLabel(for: verse.reference))
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

    private func summary(for result: BibleTextSearchResult) -> String {
        if result.isTruncated {
            return String(localized: "Showing first \(result.verses.count) of \(result.totalCount) verses")
        }
        return String(localized: "\(result.totalCount) verses")
    }
}

extension View {
    /// On macOS, offers `books` in the reference field's completion popup;
    /// choosing one fills "John " for the chapter and verse. Needs macOS 15;
    /// earlier systems, and iOS (see `BookSuggestionButtons`), keep a plain field.
    @ViewBuilder
    func bookSuggestions(_ books: [BibleBook]) -> some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            textInputSuggestions(books) { book in
                Text(book.name)
                    .textInputCompletion(book.name + " ")
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// iPad's reference field has no completion popup: matching books appear as
/// a row of buttons below it, and choosing one fills "John ".
struct BookSuggestionButtons: View {
    let books: [BibleBook]
    let choose: (BibleBook) -> Void

    var body: some View {
        if !books.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(books) { book in
                        Button(book.name) { choose(book) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("bookSuggestion-\(book.bookID)")
                    }
                }
            }
        }
    }
}
