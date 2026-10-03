//
//  BibleReaderView+Pad.swift
//  OpenBibleAI
//
//  iPad at regular width: a sidebar (search, books → chapters) next to the
//  reader, with the chat in an inspector that can be shown or hidden.
//

#if os(iOS)
import BibleDomain
import SwiftUI

extension BibleReaderView {
    var padLayout: some View {
        NavigationSplitView {
            NavigationStack(path: Bindable(appNavigation).sidebarPath) {
                padSidebarRoot
                    .navigationDestination(for: AppNavigation.ReadRoute.self) { _ in
                        padChapters
                    }
            }
            .onChange(of: selectedBookID) { _, bookID in
                // Search, restoration and cross-book steps also change the
                // book; show its chapters whenever that happens.
                if bookID != nil, appNavigation.sidebarPath.isEmpty {
                    appNavigation.showChapters()
                }
            }
        } detail: {
            readerContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if !appNavigation.isChatInspectorPresented {
                            askAboutVerseButton(compact: false)
                        }
                        ChapterNavigationBar(navigation: navigation)
                    }
                }
                .navigationTitle(locationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        BibleCompareMenu(model: compare, library: library, primary: version)
                        BibleVersionMenu(library: library, current: version, switchVersion: switchVersion)
                        Button {
                            isShowingSettings = true
                        } label: {
                            Label("AI Settings", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("aiSettingsButton")
                        Button {
                            appNavigation.isChatInspectorPresented.toggle()
                        } label: {
                            Label("Bible Chat", systemImage: "bubble.left.and.bubble.right")
                        }
                        .accessibilityIdentifier("chatInspectorToggle")
                    }
                }
                .inspector(isPresented: Bindable(appNavigation).isChatInspectorPresented) {
                    chatView()
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
                }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                AISettingsView(engine: aiEngine, semanticSearch: semanticSearch)
                    .navigationTitle("AI Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingSettings = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var padSidebarRoot: some View {
        Group {
            if searchMode == .text {
                List {
                    Section("Results") {
                        TextSearchResultRows(model: textSearchModel, catalogModel: catalogModel) { verse in
                            navigation.open(verse)
                        }
                    }
                }
            } else {
                bookList { bookID in
                    navigation.selectBook(bookID)
                    appNavigation.showChapters()
                }
            }
        }
        .safeAreaInset(edge: .top) { searchControls }
        .navigationTitle("Bible")
    }

    @ViewBuilder
    private var padChapters: some View {
        if let bookID = selectedBookID {
            ScrollView {
                chapterGrid(for: bookID) { chapter in
                    navigation.selectChapter(chapter, in: bookID)
                }
                .padding()
            }
            .navigationTitle(bookName(for: bookID) ?? bookID)
        }
    }
}
#endif
