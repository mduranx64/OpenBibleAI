//
//  BibleReaderView+Phone.swift
//  OpenBibleAI
//
//  iPhone (and iPad in narrow Split View): Read, Chat, Search and Library
//  tabs. Read is a stack: books → chapters → reader.
//

#if os(iOS)
import BibleDomain
import SwiftUI

extension BibleReaderView {
    var phoneLayout: some View {
        TabView(selection: Bindable(appNavigation).tab) {
            NavigationStack(path: Bindable(appNavigation).readPath) {
                bookList { bookID in
                    navigation.selectBook(bookID)
                    appNavigation.showChapters()
                }
                .navigationTitle("Bible")
                .navigationDestination(for: AppNavigation.ReadRoute.self) { route in
                    switch route {
                    case .chapters: phoneChapters
                    case .reader: phoneReader
                    }
                }
            }
            .tabItem { Label("Read", systemImage: "book") }
            .tag(AppNavigation.Tab.read)

            NavigationStack {
                chatView(showsHeader: false)
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            .tag(AppNavigation.Tab.chat)

            NavigationStack {
                PhoneSearchView(
                    navigation: navigation,
                    textSearchModel: textSearchModel,
                    catalogModel: catalogModel,
                    showReader: appNavigation.showReader
                )
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(AppNavigation.Tab.search)

            NavigationStack {
                LibraryView(
                    library: library,
                    compare: compare,
                    version: version,
                    switchVersion: switchVersion,
                    aiEngine: aiEngine,
                    semanticSearch: semanticSearch
                )
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppNavigation.Tab.library)
        }
    }

    @ViewBuilder
    private var phoneChapters: some View {
        if let bookID = selectedBookID {
            ScrollView {
                chapterGrid(for: bookID) { chapter in
                    navigation.selectChapter(chapter, in: bookID)
                    appNavigation.showReader()
                }
                .padding()
            }
            .navigationTitle(bookName(for: bookID) ?? bookID)
        } else {
            ContentUnavailableView(
                "Select a Chapter",
                systemImage: "book.closed",
                description: Text("Choose a book and chapter to begin reading.")
            )
        }
    }

    private var phoneReader: some View {
        readerContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    askAboutVerseButton(compact: true)
                    ChapterNavigationBar(navigation: navigation, compact: true)
                }
            }
            .navigationTitle(locationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    BibleCompareMenu(model: compare, library: library, primary: version)
                    BibleVersionMenu(library: library, current: version, switchVersion: switchVersion)
                }
            }
    }

    /// Shown while the selected verse is attached to the next question:
    /// opens the chat to ask about it (selecting attaches silently, and on
    /// iPhone the chat is on another tab).
    @ViewBuilder
    func askAboutVerseButton(compact: Bool) -> some View {
        if let attached = chatModel.attachedVerse, attached.verse.reference == activeReference {
            Button {
                appNavigation.showChat(compact: compact)
            } label: {
                Label("Ask about \(attached.title)", systemImage: "bubble.left.and.text.bubble.right")
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.bottom, 8)
            .accessibilityIdentifier("askAboutVerseButton")
        }
    }
}

/// One search field for references ("John 3:16", anything with a colon)
/// and words; a found reference opens in the Read tab.
struct PhoneSearchView: View {
    let navigation: BibleReaderNavigationModel
    let textSearchModel: BibleTextSearchModel
    let catalogModel: BibleCatalogModel
    let showReader: () -> Void

    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isReference: Bool { trimmed.contains(":") }

    var body: some View {
        List {
            if isReference {
                Section {
                    referenceStatus
                }
            } else {
                Section {
                    TextSearchResultRows(model: textSearchModel, catalogModel: catalogModel) { verse in
                        navigation.open(verse)
                        showReader()
                    }
                } footer: {
                    Text("All words, any order. Use quotes for a phrase. For a verse, type a reference like John 3:16.")
                }
            }
        }
        .navigationTitle("Search")
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("John 3:16 or words")
        )
        .onSubmit(of: .search, submit)
        .onChange(of: query) { _, _ in
            navigation.cancelSearch()
            textSearchModel.cancel()
        }
    }

    @ViewBuilder
    private var referenceStatus: some View {
        switch navigation.searchModel.state {
        case .loading:
            HStack {
                ProgressView()
                Text("Finding verse…")
            }
        case let .failed(_, message):
            Text(message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("referenceSearchError")
        default:
            Text("Full book name, chapter:verse")
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        if isReference {
            let query = trimmed
            let revision = navigation.selectionRevision
            Task {
                await navigation.search(query).value
                if navigation.selectionRevision != revision { showReader() }
            }
        } else {
            textSearchModel.submit(trimmed)
        }
    }
}

/// The reading version, Manage Bibles, versions to compare and AI Settings.
struct LibraryView: View {
    let library: BibleLibraryModel
    let compare: BibleCompareModel
    let version: BibleVersion
    let switchVersion: (String) -> Void
    let aiEngine: AIEngineModel
    let semanticSearch: SemanticSearchModel

    var body: some View {
        List {
            Section("Reading") {
                ForEach(library.installedVersions) { installed in
                    Button {
                        switchVersion(installed.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(installed.name)
                                Text(installed.abbreviation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if installed.id == version.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("readVersion-\(installed.id)")
                    .accessibilityAddTraits(installed.id == version.id ? .isSelected : [])
                }

                NavigationLink {
                    BibleVersionList(library: library, allowsDelete: true)
                        .navigationTitle("Bibles")
                        .task { await library.refresh() }
                } label: {
                    Label("Manage Bibles…", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("manageBiblesButton")
            }

            Section {
                let candidates = library.installedVersions.filter { $0.id != version.id }
                if candidates.isEmpty {
                    Text("Download another version to compare.")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates) { candidate in
                    let isShown = compare.columnIDs(excluding: version.id).contains(candidate.id)
                    Toggle(
                        "\(candidate.name) (\(candidate.abbreviation))",
                        isOn: Binding(
                            get: { isShown },
                            set: { $0 ? compare.add(candidate.id) : compare.remove(candidate.id) }
                        )
                    )
                    .disabled(!isShown && !compare.canAdd)
                    .accessibilityIdentifier("compareToggle-\(candidate.id)")
                }
            } header: {
                Text("Compare")
            } footer: {
                Text("Chapters show these versions verse by verse under the reading version.")
            }

            Section {
                NavigationLink {
                    AISettingsView(engine: aiEngine, semanticSearch: semanticSearch)
                        .navigationTitle("AI Settings")
                } label: {
                    Label("AI Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("aiSettingsButton")
            }
        }
        .navigationTitle("Library")
    }
}
#endif
