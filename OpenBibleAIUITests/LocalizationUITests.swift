import XCTest

/// The app follows the system language (Spanish and Brazilian Portuguese).
@MainActor
final class LocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSpanishInterface() {
        expectNewChatLabel("Nuevo chat", language: "es", locale: "es_ES")
    }

    func testBrazilianPortugueseInterface() {
        expectNewChatLabel("Nova conversa", language: "pt-BR", locale: "pt_BR")
    }

    private func expectNewChatLabel(_ label: String, language: String, locale: String) {
        let app = XCUIApplication()
        app.launchForUITest(arguments: ["-AppleLanguages", "(\(language))", "-AppleLocale", locale])

        let newChat = app.buttons["newChatButton"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 15))
        XCTAssertEqual(newChat.label, label)
    }
}
