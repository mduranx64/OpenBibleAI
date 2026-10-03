import Testing
@testable import OpenBibleAI

@MainActor
struct AppNavigationTests {
    @Test func showReaderOpensTheChapterInTheReadTab() {
        let navigation = AppNavigation()
        navigation.tab = .chat

        navigation.showReader()

        #expect(navigation.tab == .read)
        #expect(navigation.readPath == [.chapters, .reader])
    }

    @Test func showChatUsesTheTabWhenCompactAndTheInspectorOtherwise() {
        let navigation = AppNavigation()
        navigation.isChatInspectorPresented = false

        navigation.showChat(compact: false)
        #expect(navigation.isChatInspectorPresented)
        #expect(navigation.tab == .read)

        navigation.showChat(compact: true)
        #expect(navigation.tab == .chat)
    }

    @Test func restoredChapterOpensTheReaderButKeepsWhereTheUserIs() {
        let navigation = AppNavigation()
        navigation.positionRestored(hasChapter: true)
        #expect(navigation.readPath == [.chapters, .reader])

        // After a version switch the user may be on the chapter grid.
        navigation.readPath = [.chapters]
        navigation.positionRestored(hasChapter: true)
        #expect(navigation.readPath == [.chapters])
    }

    @Test func noRestoredChapterReturnsToTheBookList() {
        let navigation = AppNavigation()
        navigation.readPath = [.chapters, .reader]

        // e.g. the new version lacks the book being read.
        navigation.positionRestored(hasChapter: false)

        #expect(navigation.readPath.isEmpty)
    }

    @Test func sidebarPathLeavesTheReaderToTheDetailColumn() {
        let navigation = AppNavigation()
        navigation.showReader()
        #expect(navigation.sidebarPath == [.chapters])

        // Going back to the books on iPad keeps the reader for the tabs.
        navigation.sidebarPath = []
        #expect(navigation.readPath == [.reader])

        navigation.sidebarPath = [.chapters]
        #expect(navigation.readPath == [.chapters, .reader])
    }
}
