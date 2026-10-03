//
//  AppNavigation.swift
//  OpenBibleAI
//

import Observation

/// Where the user is on iPhone and iPad: the selected tab, the Read stack
/// (books → chapters → reader) and whether the chat inspector is open.
/// What is selected (book, chapter, verse) stays in
/// `BibleReaderNavigationModel`; this only decides which screen shows it.
/// Owned above the reader so it survives version switches and size-class
/// changes (iPad Split View switching between tabs and the split layout).
@MainActor
@Observable
final class AppNavigation {
    enum Tab: Hashable {
        case read
        case chat
        case search
        case library
    }

    /// Screens pushed on the Read stack after the book list.
    enum ReadRoute: Hashable {
        /// The selected book's chapter grid.
        case chapters
        /// The selected chapter.
        case reader
    }

    var tab: Tab = .read
    var readPath: [ReadRoute] = []
    /// Open by default so iPad shows reading and chat side by side, as on Mac.
    var isChatInspectorPresented = true

    /// The iPad sidebar stack: the Read stack without the reader, which the
    /// split layout shows in its detail column. Popping the chapter grid
    /// keeps the reader for when the layout becomes tabs again.
    var sidebarPath: [ReadRoute] {
        get { readPath.filter { $0 != .reader } }
        set { readPath = newValue + (readPath.contains(.reader) ? [.reader] : []) }
    }

    /// Shows the selected chapter: after a search, a citation or a source.
    func showReader() {
        readPath = [.chapters, .reader]
        tab = .read
    }

    /// Shows the selected book's chapters.
    func showChapters() {
        readPath = [.chapters]
    }

    /// Shows the chat: its tab in the compact layout, the inspector otherwise.
    func showChat(compact: Bool) {
        if compact {
            tab = .chat
        } else {
            isChatInspectorPresented = true
        }
    }

    /// After launch or a version switch: open the restored chapter, or go
    /// back to the book list when there is none (e.g. the new version lacks
    /// the book).
    func positionRestored(hasChapter: Bool) {
        if hasChapter {
            if readPath.isEmpty { readPath = [.chapters, .reader] }
        } else {
            readPath = []
        }
    }
}
