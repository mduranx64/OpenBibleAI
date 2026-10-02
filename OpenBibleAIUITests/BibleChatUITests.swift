import XCTest

@MainActor
final class BibleChatUITests: XCTestCase {
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

    private func chip(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["attachedVerseChip"]
    }

    private func expectChip(_ title: String, in app: XCUIApplication) {
        let chip = chip(in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "Selecting a verse attaches it to the chat")
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", title, title),
            object: chip
        )
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed, "Chip shows \(title)")
    }

    func testSelectedVerseAttachesAsAChipThatCanBeRemoved() {
        let app = XCUIApplication()
        launch(app)

        XCTAssertTrue(app.textFields["chatInputField"].waitForExistence(timeout: 15),
                      "The chat is available without selecting a verse")
        XCTAssertFalse(app.descendants(matching: .any)["aiPanelModePicker"].exists, "There is a single chat panel")

        search("John 3:16", in: app)
        expectChip("John 3:16", in: app)

        search("1 John 2:1", in: app)
        expectChip("1 John 2:1", in: app)
        XCTAssertFalse(app.staticTexts["generatedAnswerLabel"].exists, "No generated label before asking")

        app.buttons["removeAttachedVerseButton"].click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: chip(in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "✕ removes the attached verse")
        XCTAssertTrue(app.textFields["chatInputField"].exists)

        app.buttons["verse-1JO-2-1"].click()
        expectChip("1 John 2:1", in: app)
        app.terminate()
    }

    /// Uses the real on-device model, so it only runs when asked:
    /// `TEST_RUNNER_OPENBIBLE_LIVE_ASK=1`. It saves a chat in the app's data.
    func testLiveFollowUpCitesVersesAndOpeningASourceKeepsTheChat() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_ASK"] == "1",
                          "Set TEST_RUNNER_OPENBIBLE_LIVE_ASK=1 to run against the real model")
        let app = XCUIApplication()
        launch(app)

        let field = app.textFields["chatInputField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        if app.buttons["newChatButton"].isEnabled { app.buttons["newChatButton"].click() }

        field.click()
        field.typeText("Where was Jesus born?\n")
        let sources = app.buttons.matching(identifier: "chatSources")
        XCTAssertTrue(sources.firstMatch.waitForExistence(timeout: 120), "The first answer completes with sources")

        field.click()
        field.typeText("Who was the king then?\n")
        let second = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: sources)
        XCTAssertEqual(XCTWaiter.wait(for: [second], timeout: 120), .completed, "The follow-up completes")
        XCTAssertEqual(app.staticTexts.matching(identifier: "chatQuestion").count, 2)

        sources.element(boundBy: 1).click()
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chatSource-'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let verseID = source.identifier.replacingOccurrences(of: "chatSource-", with: "verse-")
        source.click()

        XCTAssertTrue(app.buttons[verseID].waitForExistence(timeout: 15), "The source verse opens in the reader")
        XCTAssertEqual(app.staticTexts.matching(identifier: "chatAnswer").count, 2, "The chat stays visible")
        XCTAssertFalse(chip(in: app).exists, "Opening a source doesn't attach it")

        // The chat is saved: after relaunch it is listed and reopens.
        app.terminate()
        launch(app)
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 15))
        app.buttons["chatHistoryButton"].click()
        let row = app.buttons.matching(identifier: "chatHistoryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saved chats are listed")
        row.click()
        let reopened = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 2"),
            object: app.staticTexts.matching(identifier: "chatQuestion")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 10), .completed, "Both turns come back")
        app.terminate()
    }
}
