import XCTest

/// With no Bible installed, the app asks for one, downloads it (from the
/// local test server) and opens the reader.
@MainActor
final class BibleOnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchDownloadsTheChosenBibleAndStartsReading() {
        let app = XCUIApplication()
        app.launchForUITest(bibles: .fresh)

        let start = app.buttons["onboardingContinueButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertFalse(start.isEnabled, "Nothing to read before a Bible is installed")

        let download = app.buttons["downloadBible-kjv"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.click()

        let installed = app.descendants(matching: .any)["bibleInstalled-kjv"].waitForExistence(timeout: 60)
        XCTAssertTrue(installed, String(describing: app.staticTexts["bibleDownloadError-kjv"].value))
        XCTAssertTrue(start.isEnabled)
        start.click()

        XCTAssertTrue(app.buttons["book-GEN"].waitForExistence(timeout: 15) || app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
    }
}
