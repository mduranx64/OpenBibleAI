import XCTest

@MainActor
final class ReferenceSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches and brings the app forward, then requires a window. Without a
    /// window every later query fails with a bare "XCTAssertTrue failed", which
    /// looks like a feature bug but is a desktop/launch problem.
    ///
    /// Launch arguments skip macOS's persisted window state, which can restore
    /// the app with no window (e.g. a frame saved on a disconnected display).
    /// If no window still appears, fall back to File > New Window (Cmd+N).
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

    private func search(_ query: String, in app: XCUIApplication, pressReturn: Bool = false) {
        let field = app.textFields["referenceSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(query)
        if pressReturn {
            field.typeText("\n")
        } else {
            app.buttons["referenceSearchButton"].click()
        }
    }

    private func expectSelected(_ identifier: String, in app: XCUIApplication) {
        let verse = app.buttons[identifier]
        XCTAssertTrue(verse.waitForExistence(timeout: 10))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: verse)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        XCTAssertTrue(verse.isHittable, "The selected verse should be scrolled into view")
        XCTAssertTrue(app.staticTexts["Ask About This Verse"].waitForExistence(timeout: 10))
    }

    func testSearchSelectionErrorsAndLongChapter() {
        let app = XCUIApplication()
        launch(app)
        search("John 3:16", in: app, pressReturn: true)
        expectSelected("verse-JOH-3-16", in: app)

        search("John 999:999", in: app)
        XCTAssertTrue(app.staticTexts["referenceSearchError"].waitForExistence(timeout: 10))
        expectSelected("verse-JOH-3-16", in: app)

        search("1 John 2:1", in: app)
        expectSelected("verse-1JO-2-1", in: app)

        search("Psalms 119:176", in: app)
        // expectSelected already proves the verse is selected and hittable
        // (scrolled into view); a manual screenshot only adds a failure mode.
        expectSelected("verse-PSA-119-176", in: app)
        app.terminate()
    }

    func testChapterBoundariesAndRelaunchRestoration() {
        let app = XCUIApplication()
        launch(app)
        // Previous/Next cross book boundaries and stop only at the first
        // chapter of Genesis and the last chapter of Revelation.
        search("Genesis 1:1", in: app)
        expectSelected("verse-GEN-1-1", in: app)
        XCTAssertFalse(app.buttons["Previous Chapter"].isEnabled)
        XCTAssertTrue(app.buttons["Next Chapter"].isEnabled)

        search("Revelation 22:21", in: app)
        expectSelected("verse-REV-22-21", in: app)
        XCTAssertTrue(app.buttons["Previous Chapter"].isEnabled)
        XCTAssertFalse(app.buttons["Next Chapter"].isEnabled)

        search("Genesis 50:26", in: app)
        expectSelected("verse-GEN-50-26", in: app)
        XCTAssertTrue(app.buttons["Next Chapter"].isEnabled, "Genesis 50 continues to Exodus 1")
        app.terminate()
        launch(app)
        // Restoration intentionally saves chapter only, not verse or scroll offset.
        let verse = app.buttons["verse-GEN-50-1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 15))
        XCTAssertFalse(verse.isSelected)
        XCTAssertTrue(app.staticTexts["Select a verse to begin studying."].exists)
        app.terminate()
    }
}
