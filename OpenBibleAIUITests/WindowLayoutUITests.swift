import XCTest

@MainActor
final class WindowLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Same launch hardening as `ReferenceSearchUITests`. This skips macOS
    /// window-state restoration only; the autosaved window frame and split
    /// column widths still apply, so the test sees any previously saved
    /// layout (the narrow-column case this guards against) and cannot assert
    /// the first-launch `defaultSize`.
    private static let windowFrameKey =
        "NSWindow Frame SwiftUI.WindowGroup<OpenBibleAI.ContentView>-1-AppWindow-1"
    private static let splitFramesKey =
        "NSSplitView Subview Frames SwiftUI.WindowGroup<OpenBibleAI.ContentView>-1-AppWindow-1, SidebarNavigationSplitView"

    private func launch(_ app: XCUIApplication, discardingSavedLayout: Bool = false) {
        // Launch arguments override the saved defaults for this run only,
        // so the app behaves as on a first launch.
        app.launchForUITest(arguments: discardingSavedLayout
            ? ["-\(Self.windowFrameKey)", "", "-\(Self.splitFramesKey)", ""]
            : [])
    }

    func testReadingColumnKeepsRoomEvenWithTheStudyPanelOpen() {
        let app = XCUIApplication()
        launch(app)

        let field = app.textFields["referenceSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.click()
        field.typeText("John 3:16")
        app.buttons["referenceSearchButton"].click()

        // Searching selects the verse, which also attaches it to the chat
        // panel: the case where the reading column was squeezed the most.
        let verse = app.buttons["verse-JOH-3-16"]
        XCTAssertTrue(verse.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["attachedVerseChip"].waitForExistence(timeout: 10))
        // A verse row sits about 120 pt inside its column. It measured 135
        // (column ~200) before the fix and ~323 (column ~445) after.
        XCTAssertGreaterThanOrEqual(
            verse.frame.width, 300,
            "The reading column is too narrow to read comfortably"
        )
        app.terminate()
    }

    func testFirstLaunchOpensWideWithAGenerousReadingColumn() {
        let app = XCUIApplication()
        launch(app, discardingSavedLayout: true)

        XCTAssertGreaterThanOrEqual(
            app.windows.firstMatch.frame.width, 1200,
            "The window should open wide enough for three columns"
        )

        let field = app.textFields["referenceSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.click()
        field.typeText("John 3:16")
        app.buttons["referenceSearchButton"].click()

        let verse = app.buttons["verse-JOH-3-16"]
        XCTAssertTrue(verse.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["attachedVerseChip"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(
            verse.frame.width, 400,
            "On first launch the reading column should be well above its minimum"
        )
        app.terminate()
    }
}
