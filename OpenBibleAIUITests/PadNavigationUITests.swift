#if os(iOS)
import XCTest

/// The iPad split layout: sidebar, reader and the chat inspector. Run on an
/// iPad simulator. Screenshots are attached to the result bundle.
@MainActor
final class PadNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSidebarReaderAndChatInspector() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The split layout is checked on iPad.")
        }
        let app = XCUIApplication()
        app.launchForUITest(arguments: ["-bible.readingPosition", ""])

        // The chat starts open beside the reader.
        XCTAssertTrue(app.descendants(matching: .any)["chatInputField"].waitForExistence(timeout: 15))

        let filter = app.textFields["bookFilterField"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        filter.typeText("John")
        app.buttons["book-JOH"].tap()
        let chapter = app.buttons["chapter-JOH-3"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.tap()
        let verse = app.buttons["verse-JOH-3-3"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10))
        verse.tap()
        XCTAssertTrue(app.descendants(matching: .any)["attachedVerseChip"].waitForExistence(timeout: 10))
        screenshot("Pad reader and chat", app)

        // Hide the chat: the reader offers Ask about, which shows it again.
        app.buttons["chatInspectorToggle"].tap()
        let ask = app.buttons["askAboutVerseButton"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        screenshot("Pad reader, chat hidden", app)
        ask.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatInputField"].waitForExistence(timeout: 10))

        app.buttons["aiSettingsButton"].tap()
        XCTAssertTrue(app.navigationBars["AI Settings"].waitForExistence(timeout: 10))
        screenshot("Pad AI Settings", app)
    }

    func testBookSuggestionCompletesTheReference() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The split layout is checked on iPad.")
        }
        let app = XCUIApplication()
        app.launchForUITest(arguments: ["-bible.readingPosition", ""])

        let field = app.textFields["referenceSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("1 Jo")
        let suggestion = app.buttons["bookSuggestion-1JO"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["bookSuggestion-JOH"].exists, "1 Jo matches only 1 John")
        screenshot("Pad book suggestions", app)
        suggestion.tap()

        XCTAssertEqual(field.value as? String, "1 John ")
        XCTAssertFalse(suggestion.exists, "A complete name suggests nothing")
        field.typeText("2:1\n")
        XCTAssertTrue(app.buttons["verse-1JO-2-1"].waitForExistence(timeout: 15))
    }
}
#endif
