import XCTest

@MainActor
final class SidebarNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func expectTitle(_ text: String, in app: XCUIApplication) {
        let title = app.staticTexts["chapterTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR label == %@", text, text),
            object: title
        )
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed, "Expected heading \(text)")
    }

    private func expectSelected(_ identifier: String, in app: XCUIApplication) {
        let verse = app.buttons[identifier]
        XCTAssertTrue(verse.waitForExistence(timeout: 10))
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: verse
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
    }

    func testDrillDownFilterShortcutsAndCrossBookNext() {
        let app = XCUIApplication()
        app.launchForUITest()

        // A restored reading position opens the chapter grid; go back first.
        let back = app.buttons["backToBooksButton"]
        if back.waitForExistence(timeout: 5) { back.click() }

        // Filter the testament-grouped book list.
        let filter = app.textFields["bookFilterField"]
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        filter.click()
        filter.typeText("john")
        XCTAssertTrue(app.buttons["book-JOH"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["book-1JO"].exists)
        XCTAssertFalse(app.buttons["book-GEN"].exists, "Filter should hide non-matching books")

        // Drill into John, pick chapter 3 from the grid.
        app.buttons["book-JOH"].click()
        let chapterThree = app.buttons["chapter-JOH-3"]
        XCTAssertTrue(chapterThree.waitForExistence(timeout: 10))
        chapterThree.click()
        expectTitle("John 3", in: app)
        XCTAssertTrue(app.buttons["verse-JOH-3-1"].waitForExistence(timeout: 10))

        // Back to the book list without losing the reading position.
        app.buttons["backToBooksButton"].click()
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        expectTitle("John 3", in: app)

        // Keyboard: next chapter, then step through verses.
        app.typeKey("]", modifierFlags: .command)
        expectTitle("John 4", in: app)
        app.typeKey(.downArrow, modifierFlags: .option)
        expectSelected("verse-JOH-4-1", in: app)
        app.typeKey(.downArrow, modifierFlags: .option)
        expectSelected("verse-JOH-4-2", in: app)

        // Next on the last chapter of a book continues into the next book.
        let field = app.textFields["referenceSearchField"]
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Malachi 4:6")
        app.buttons["referenceSearchButton"].click()
        expectTitle("Malachi 4", in: app)
        // The shortcut runs the same action as the button; clicking can fail
        // to hit-test when the window sits on a secondary display.
        XCTAssertTrue(app.buttons["Next Chapter"].isEnabled)
        app.typeKey("]", modifierFlags: .command)
        expectTitle("Matthew 1", in: app)
        XCTAssertTrue(app.buttons["chapter-MAT-1"].waitForExistence(timeout: 10), "Sidebar follows to the new book")
        app.terminate()
    }
}
