import XCTest

@MainActor
final class StudyPanelUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Same launch hardening as `ReferenceSearchUITests`.
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

    private func search(_ query: String, in app: XCUIApplication) {
        let field = app.textFields["referenceSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(query)
        app.buttons["referenceSearchButton"].click()
    }

    private func expectReference(_ text: String, in app: XCUIApplication) {
        let label = app.staticTexts["studyVerseReference"]
        XCTAssertTrue(label.waitForExistence(timeout: 15))
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR label == %@", text, text),
            object: label
        )
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed)
    }

    func testStudyPanelShowsFullBookNameCardAndNoGeneratedLabelBeforeAsking() {
        let app = XCUIApplication()
        launch(app)

        search("John 3:16", in: app)
        expectReference("John 3:16", in: app)
        XCTAssertTrue(app.staticTexts["Ask About This Verse"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.staticTexts["generatedAnswerLabel"].exists,
            "Generated-answer label must not appear before a question is asked"
        )

        search("1 John 2:1", in: app)
        expectReference("1 John 2:1", in: app)
        XCTAssertFalse(app.staticTexts["generatedAnswerLabel"].exists)
        app.terminate()
    }
}
