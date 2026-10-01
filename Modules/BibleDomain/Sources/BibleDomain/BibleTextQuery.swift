//
//  BibleTextQuery.swift
//  BibleDomain
//

import Foundation

/// A parsed word/phrase search.
///
/// Each term must appear in a verse (all terms, any order). A term with one
/// word matches that whole word; a term with several words, written in
/// double quotes, matches those words consecutively. Words are lowercased,
/// diacritic-folded, and split on anything that is not a letter or digit.
public struct BibleTextQuery: Equatable, Sendable {
    public let terms: [[String]]

    public init(_ rawValue: String) throws(ParseError) {
        var terms: [[String]] = []

        // Splitting on `"` alternates unquoted (even) and quoted (odd)
        // segments; an unterminated quote leaves the remainder quoted.
        let segments = rawValue.split(
            separator: "\"",
            omittingEmptySubsequences: false
        )

        for (index, segment) in segments.enumerated() {
            let words = Self.words(in: String(segment))

            if index.isMultiple(of: 2) {
                terms.append(contentsOf: words.map { [$0] })
            } else if !words.isEmpty {
                terms.append(words)
            }
        }

        let characterCount = terms.joined().reduce(0) { $0 + $1.count }

        guard characterCount >= Self.minimumCharacterCount else {
            throw .tooShort
        }

        self.terms = terms
    }

    /// Whether every term appears in `text`.
    func matches(_ text: String) -> Bool {
        let words = Self.words(in: text)

        return terms.allSatisfy { term in
            Self.contains(term, in: words)
        }
    }

    static let minimumCharacterCount = 2

    static func words(in text: String) -> [String] {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
    }

    private static func contains(
        _ term: [String],
        in words: [String]
    ) -> Bool {
        guard let first = term.first else { return true }

        if term.count == 1 {
            return words.contains(first)
        }

        guard words.count >= term.count else { return false }

        for start in 0...(words.count - term.count)
        where words[start] == first
            && words[start...].starts(with: term)
        {
            return true
        }

        return false
    }

    public enum ParseError: Error, Equatable, Sendable {
        case tooShort
    }
}
