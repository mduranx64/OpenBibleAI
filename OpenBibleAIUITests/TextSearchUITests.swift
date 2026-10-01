import XCTest

@MainActor
final class TextSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Same launch hardening as `ReferenceSearchUITests`: skip persisted window
    /// state, then require a window so failures name the real problem.
    private func launch(_ app: XCUIApplication) {
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "OpenBibleAI launched without a window; check that the app is not hidden or on a disconnected display"
        )
    }

    private func switchToTextSearch(in app: XCUIApplication) {
        let picker = app.radioButtons["Text"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.click()
    }

    private func textSearch(_ query: String, in app: XCUIApplication) {
        let field = app.textFields["textSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(query)
        app.buttons["textSearchButton"].click()
    }

    func testTextSearchOpensResultAndShowsStatuses() {
        let app = XCUIApplication()
        launch(app)
        switchToTextSearch(in: app)

        textSearch("\"in the beginning\"", in: app)
        let first = app.buttons["textSearchResult-GEN-1-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        first.click()

        let verse = app.buttons["verse-GEN-1-1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10))
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: verse
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["Ask About This Verse"].waitForExistence(timeout: 10))

        textSearch("zzzqxj", in: app)
        XCTAssertTrue(app.staticTexts["No verses match."].waitForExistence(timeout: 10))

        textSearch("a", in: app)
        XCTAssertTrue(app.staticTexts["Enter at least two letters."].waitForExistence(timeout: 10))
        app.terminate()
    }
}
