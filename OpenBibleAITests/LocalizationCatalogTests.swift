import Foundation
import Testing

/// Every string in the app's String Catalog is translated into each shipped
/// language, keeping the source's format placeholders.
struct LocalizationCatalogTests {
    static let languages = ["es", "pt-BR"]

    @Test(arguments: languages)
    func everyStringIsTranslatedWithMatchingPlaceholders(language: String) throws {
        let catalogURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "OpenBibleAI/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))

        #expect(!catalog.strings.isEmpty)
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            let values = entry.localizations?[language]?.values ?? []
            #expect(!values.isEmpty, "\(language) is missing \"\(key)\"")
            for value in values {
                #expect(value.state == "translated", "\(language) \"\(key)\" is \(value.state)")
                #expect(
                    Self.placeholders(in: value.value) == Self.placeholders(in: key),
                    "\(language) \"\(key)\" → \"\(value.value)\" changes the placeholders"
                )
            }
        }
    }

    /// Format specifiers such as `%@`, `%lld` and `%%`, in order.
    static func placeholders(in text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(?:lld|ld|d|@|f|%)/).map { String($0.output) }
    }

    struct Catalog: Decodable {
        let strings: [String: Entry]
    }

    struct Entry: Decodable {
        let shouldTranslate: Bool?
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit?
        let variations: Variations?

        var values: [StringUnit] {
            if let stringUnit { return [stringUnit] }
            return variations?.plural?.values.compactMap(\.stringUnit) ?? []
        }
    }

    struct Variations: Decodable {
        let plural: [String: Localization]?
    }

    struct StringUnit: Decodable {
        let state: String
        let value: String
    }
}
