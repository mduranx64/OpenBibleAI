import Foundation

/// Catalog books whose name begins with what has been typed, for completing
/// the book part of a reference ("jo" → Joshua, Job, …, 1 John).
///
/// Matching uses `BibleReferenceParser`'s normalization (case, diacritics and
/// whitespace), so a chosen name always parses. Names that start with the input
/// come first, then numbered books whose name after the number does ("jo" →
/// 1 John); each group keeps canonical order. A complete name, or a name
/// followed by a chapter, suggests nothing.
public enum BibleBookSuggestions {
    public static func matching(_ input: String, in books: [BibleBook], limit: Int = 8) -> [BibleBook] {
        let query = BibleReferenceParser.normalized(input)
        guard !query.isEmpty, limit > 0 else { return [] }

        let ordered = books.sorted { $0.canonicalOrder < $1.canonicalOrder }
        let names = ordered.map { BibleReferenceParser.normalized($0.name) }
        guard !names.contains(query) else { return [] }

        let byName = ordered.indices.filter { names[$0].hasPrefix(query) }
        let byNameAfterNumber = ordered.indices.filter { index in
            !byName.contains(index) && nameAfterNumber(names[index])?.hasPrefix(query) == true
        }
        return (byName + byNameAfterNumber).prefix(limit).map { ordered[$0] }
    }

    /// "1 john" → "john"; nil for names that don't start with a number.
    private static func nameAfterNumber(_ name: String) -> Substring? {
        let words = name.split(separator: " ", maxSplits: 1)
        guard words.count == 2, words[0].allSatisfy(\.isNumber) else { return nil }
        return words[1]
    }
}
