import XCTest

@MainActor
final class ReferenceSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
        XCTAssertTrue(app.descendants(matching: .any)["attachedVerseChip"].waitForExistence(timeout: 10), "The selected verse attaches to the chat")
    }

    func testSearchSelectionErrorsAndLongChapter() {
        let app = XCUIApplication()
        app.launchForUITest()
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
        app.launchForUITest()
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
        app.launchForUITest()
        // Restoration intentionally saves chapter only, not verse or scroll offset.
        let verse = app.buttons["verse-GEN-50-1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 15))
        XCTAssertFalse(verse.isSelected)
        // With no verse selected the chat has no verse attached.
        XCTAssertTrue(app.textFields["chatInputField"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["attachedVerseChip"].exists)
        app.terminate()
    }
}
