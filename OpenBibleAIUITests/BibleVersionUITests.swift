import XCTest

/// Switching the reading version changes the text's book names and keeps
/// the reader usable; extra versions can be deleted, the one in use can't.
@MainActor
final class BibleVersionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func chooseVersion(_ title: String, in app: XCUIApplication) {
        let menu = app.descendants(matching: .any)["versionMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.click()
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No menu item \(title)")
        item.click()
    }

    private func expectBookName(_ name: String, in app: XCUIApplication) {
        let back = app.buttons["backToBooksButton"]
        if back.waitForExistence(timeout: 3) { back.click() }
        let genesis = app.buttons["book-GEN"]
        XCTAssertTrue(genesis.waitForExistence(timeout: 15))
        let named = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", name), object: genesis)
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 10), .completed, "Expected \(name), got \(genesis.label)")
    }

    func testComparingVersionsInAlignedColumns() {
        let app = XCUIApplication()
        app.launchForUITest(bibles: .installed(["kjv", "test-es"]))
        chooseVersion("King James Version (KJV)", in: app)

        let field = app.textFields["referenceSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("John 3:16")
        app.buttons["referenceSearchButton"].click()
        XCTAssertTrue(app.buttons["verse-JOH-3-16"].waitForExistence(timeout: 15))

        let compare = app.descendants(matching: .any)["compareMenu"].firstMatch
        compare.click()
        app.menuItems["UI Test (Spanish book names) (TES)"].click()

        XCTAssertTrue(app.descendants(matching: .any)["compareView"].waitForExistence(timeout: 15))
        let row = app.buttons["compareRow-16"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Verse 16 row")
        XCTAssertEqual(row.label.components(separatedBy: "For God so loved the world").count - 1, 2, "Both columns show verse 16: \(row.label)")

        // Selecting a row selects the verse and attaches it to the chat.
        app.buttons["compareRow-17"].click()
        let chip = app.descendants(matching: .any)["attachedVerseChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "John 3:17", "John 3:17"), object: chip)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed)

        compare.click()
        app.menuItems["stopComparingButton"].click()
        XCTAssertTrue(app.buttons["verse-JOH-3-16"].waitForExistence(timeout: 10), "Back to the single-version reader")
    }

    func testSwitchingVersionsAndDeletingOne() {
        let app = XCUIApplication()
        app.launchForUITest(bibles: .installed(["kjv", "test-es"]))

        chooseVersion("King James Version (KJV)", in: app)
        expectBookName("Genesis", in: app)

        chooseVersion("UI Test (Spanish book names) (TES)", in: app)
        expectBookName("Génesis", in: app)

        chooseVersion("King James Version (KJV)", in: app)
        expectBookName("Genesis", in: app)

        // Manage: the version in use has no Delete; the other one does.
        let menu = app.descendants(matching: .any)["versionMenu"].firstMatch
        menu.click()
        app.menuItems["manageBiblesButton"].click()
        XCTAssertTrue(app.descendants(matching: .any)["bibleInstalled-kjv"].waitForExistence(timeout: 10))
        let delete = app.buttons["deleteBible-test-es"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        let confirm = app.buttons["confirmDeleteBible-test-es"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(app.buttons["downloadBible-test-es"].waitForExistence(timeout: 10))
        app.buttons["manageBiblesDoneButton"].click()
    }
}
