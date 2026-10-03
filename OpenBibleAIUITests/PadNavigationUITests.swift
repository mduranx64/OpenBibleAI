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
}
#endif
