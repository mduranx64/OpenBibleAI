import Foundation


/// Parses one full catalog book name followed by an explicit chapter and verse.
///
/// Matching ignores case and diacritics ("Genesis" finds "Génesis") and
/// collapses whitespace (including tabs/newlines). `aliases` (book ID → names,
/// e.g. `BibleBookNames.aliases`) are other names for the catalog's books,
/// tried only when no catalog name matches.
/// Whitespace around `:` and leading zeros are accepted. Positions must contain
/// only ASCII decimal digits and fit in `Int`; `BibleReference` validates positivity.
/// Abbreviations, ranges, and chapter-only input are not supported.
public enum BibleReferenceParser {
    /// Resolves a name to its catalog ID, without checking stored verse availability.
    /// Throws `ParseError` for syntax/name errors or `BibleReference.ValidationError`
    /// for invalid positions. Call a `BibleRepository` before using this for navigation.
    public static func parse(
        _ input: String,
        books: [BibleBook],
        aliases: [String: [String]] = [:]
    ) throws -> BibleReference {
        let parts = input.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw ParseError.invalidSyntax }

        let bookAndChapter = parts[0].split(whereSeparator: \.isWhitespace)
        let verseParts = parts[1].split(whereSeparator: \.isWhitespace)
        guard bookAndChapter.count >= 2,
              let chapterToken = bookAndChapter.last,
              verseParts.count == 1,
              let verseToken = verseParts.first,
              let chapter = decimalInteger(chapterToken),
              let verse = decimalInteger(verseToken)
        else { throw ParseError.invalidSyntax }

        let bookName = bookAndChapter.dropLast().joined(separator: " ")
        let normalizedName = normalized(bookName)
        var matches = books.filter { normalized($0.name) == normalizedName }
        if matches.isEmpty {
            matches = books.filter { book in
                aliases[book.bookID, default: []].contains { normalized($0) == normalizedName }
            }
        }
        guard let book = matches.first else { throw ParseError.unknownBook(bookName) }
        guard matches.count == 1 else { throw ParseError.ambiguousBook(bookName) }

        return try BibleReference(bookID: book.bookID, chapter: chapter, verse: verse)
    }

    /// A book name for comparison: whitespace collapsed, case and diacritics folded.
    static func normalized(_ name: some StringProtocol) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func decimalInteger(_ token: Substring) -> Int? {
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }
        return Int(token)
    }

    public enum ParseError: Error, Equatable, Sendable {
        case invalidSyntax
        case unknownBook(String)
        case ambiguousBook(String)
    }
}
