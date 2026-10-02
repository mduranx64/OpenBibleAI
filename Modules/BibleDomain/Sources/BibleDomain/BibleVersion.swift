//
//  BibleVersion.swift
//  BibleDomain
//

/// A Bible translation the app can install, e.g. the King James Version.
/// Book IDs (GEN…REV) are shared by all versions, so a `BibleReference`
/// names the same verse in each.
public struct BibleVersion: Identifiable, Hashable, Sendable, Codable {
    /// Stable identifier, e.g. "kjv" or "rv1909".
    public let id: String
    public let name: String
    public let abbreviation: String
    /// BCP-47 code of the text's language, e.g. "en", "es", "pt-BR".
    public let languageCode: String
    /// Copyright or public-domain notice shown with the text.
    public let copyright: String

    public init(
        id: String,
        name: String,
        abbreviation: String,
        languageCode: String,
        copyright: String
    ) throws(ValidationError) {
        guard id.contains(where: { !$0.isWhitespace }) else { throw .blankID }
        guard name.contains(where: { !$0.isWhitespace }) else { throw .blankName }
        guard languageCode.contains(where: { !$0.isWhitespace }) else { throw .blankLanguage }
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.languageCode = languageCode
        self.copyright = copyright
    }

    /// Keyword-search rules for the version's language.
    public var analyzer: TextAnalyzer {
        TextAnalyzer(languageCode: languageCode)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            abbreviation: container.decode(String.self, forKey: .abbreviation),
            languageCode: container.decode(String.self, forKey: .languageCode),
            copyright: container.decode(String.self, forKey: .copyright)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case abbreviation
        case languageCode = "language"
        case copyright
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case blankID
        case blankName
        case blankLanguage
    }
}
