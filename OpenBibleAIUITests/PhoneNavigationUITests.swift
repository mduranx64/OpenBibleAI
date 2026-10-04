#if os(iOS)
import XCTest

/// The iPhone tab layout (and iPad in compact width): Read, Chat, Search and
/// Library. Run on an iPhone simulator. Screenshots are attached to the
/// result bundle for review.
@MainActor
final class PhoneNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(bibles: XCUIApplication.UITestBibles = .installed(["kjv"])) throws -> XCUIApplication {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The tab layout is checked on iPhone.")
        }
        let app = XCUIApplication()
        // Start at the book list: no restored reading position.
        app.launchForUITest(arguments: ["-bible.readingPosition", ""], bibles: bibles)
        return app
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tab(_ name: String, _ app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons[name]
    }

    /// Book rows are lazy: filter so the book is on screen, then tap it.
    private func openBook(_ name: String, id: String, _ app: XCUIApplication) {
        let filter = app.textFields["bookFilterField"]
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        filter.tap()
        filter.typeText(name)
        let book = app.buttons["book-\(id)"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
    }

    func testReadAskAndOpenCitationBack() throws {
        let app = try launch()

        XCTAssertTrue(app.buttons["book-GEN"].waitForExistence(timeout: 15))
        screenshot("1 Books", app)
        openBook("John", id: "JOH", app)

        let chapter = app.buttons["chapter-JOH-3"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        screenshot("2 Chapters", app)
        chapter.tap()

        let verse = app.buttons["verse-JOH-3-3"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Next Chapter"].exists)
        XCTAssertTrue(app.buttons["Previous Chapter"].exists)
        verse.tap()

        let ask = app.buttons["askAboutVerseButton"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        screenshot("3 Reader with verse selected", app)
        ask.tap()

        XCTAssertTrue(tab("Chat", app).isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["attachedVerseChip"].waitForExistence(timeout: 10))
        screenshot("4 Chat with attached verse", app)

        // Back in Read, the chapter is still open; the next chapter works.
        tab("Read", app).tap()
        XCTAssertTrue(verse.waitForExistence(timeout: 10))
        app.buttons["Next Chapter"].tap()
        XCTAssertTrue(app.buttons["verse-JOH-4-1"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["chapter-JOH-4"].waitForExistence(timeout: 10))
    }

    func testSearchReferenceAndTextOpenTheReader() throws {
        let app = try launch()
        tab("Search", app).tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Genesis 1:1\n")
        XCTAssertTrue(app.buttons["verse-GEN-1-1"].waitForExistence(timeout: 15))
        XCTAssertTrue(tab("Read", app).isSelected)
        screenshot("5 Reference search result", app)

        tab("Search", app).tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.buttons.firstMatch.tap() // Clear
        field.typeText("Unknown 1:1\n")
        XCTAssertTrue(app.staticTexts["referenceSearchError"].waitForExistence(timeout: 10))

        field.buttons.firstMatch.tap()
        field.typeText("without form\n")
        let result = app.buttons["textSearchResult-GEN-1-2"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        screenshot("6 Text search results", app)
        result.tap()
        XCTAssertTrue(app.buttons["verse-GEN-1-2"].waitForExistence(timeout: 10))
    }

    func testBookSuggestionCompletesTheReference() throws {
        let app = try launch()
        tab("Search", app).tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("1 Jo")
        let suggestion = app.descendants(matching: .any)["bookSuggestion-1JO"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["bookSuggestion-JOH"].exists, "1 Jo matches only 1 John")
        screenshot("7 Book suggestions", app)
        suggestion.tap()

        XCTAssertEqual(field.value as? String, "1 John ")
        field.typeText("2:1\n")
        XCTAssertTrue(app.buttons["verse-1JO-2-1"].waitForExistence(timeout: 15))
        XCTAssertTrue(tab("Read", app).isSelected)
    }

    func testLibrarySwitchesComparesAndManages() throws {
        let app = try launch(bibles: .installed(["kjv", "test-es"]))
        tab("Library", app).tap()

        let compareToggle = app.switches["compareToggle-test-es"]
        XCTAssertTrue(compareToggle.waitForExistence(timeout: 10))
        screenshot("7 Library", app)
        compareToggle.switches.firstMatch.tap()

        tab("Read", app).tap()
        openBook("John", id: "JOH", app)
        let chapter = app.buttons["chapter-JOH-3"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.tap()
        XCTAssertTrue(app.descendants(matching: .any)["compareView"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["compareRow-3"].waitForExistence(timeout: 10))
        // Stacked: the second version is on screen, not in a column off to the side.
        let secondVersion = app.descendants(matching: .any)["compareCell-1-1"]
        XCTAssertTrue(secondVersion.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(secondVersion.frame.maxX, app.windows.firstMatch.frame.maxX)
        screenshot("8 Compare", app)

        tab("Library", app).tap()
        compareToggle.switches.firstMatch.tap()
        app.buttons["manageBiblesButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bibleVersion-kjv"].waitForExistence(timeout: 10))
        screenshot("9 Manage Bibles", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["readVersion-test-es"].tap()
        tab("Read", app).tap()
        let genesis = app.buttons["book-GEN"]
        XCTAssertTrue(genesis.waitForExistence(timeout: 15))
        XCTAssertEqual(genesis.label, "Génesis")
    }

    func testSwipeDeletesAVersion() throws {
        let app = try launch(bibles: .installed(["kjv", "test-es"]))
        tab("Library", app).tap()
        let manage = app.buttons["manageBiblesButton"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.tap()

        let row = app.descendants(matching: .any)["bibleVersion-test-es"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["deleteBible-test-es"].tap()
        XCTAssertTrue(app.buttons["downloadBible-test-es"].waitForExistence(timeout: 10))
    }

    func testOnboardingFitsTheScreen() throws {
        let app = try launch(bibles: .fresh)
        let download = app.buttons["downloadBible-kjv"]
        XCTAssertTrue(download.waitForExistence(timeout: 15))
        XCTAssertTrue(download.isHittable, "Download should be on screen, not cut off")
        screenshot("0 Onboarding", app)
        download.tap()
        let start = app.buttons["onboardingContinueButton"]
        XCTAssertTrue(app.descendants(matching: .any)["bibleInstalled-kjv"].waitForExistence(timeout: 30))
        start.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
    }
}
#endif
