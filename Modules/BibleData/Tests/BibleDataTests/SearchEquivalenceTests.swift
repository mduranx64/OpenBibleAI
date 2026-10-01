//
//  SearchEquivalenceTests.swift
//  BibleData
//

import Foundation
import Testing
import BibleData
import BibleDomain

/// Guards search optimizations: results over the full bundled KJV must equal
/// a straightforward reference matcher that tokenizes with Foundation
/// folding and `Character` properties (the original, unoptimized rules).
struct SearchEquivalenceTests {
    private static let queries = [
        "the", "lord", "leviathan", "zzzqxj", "love one another",
        "\"in the beginning\"", "be", "Élan", "God's", "LORD,",
        "\"thou shalt not\" kill", "1", "o"
    ]

    @Test
    func optimizedSearchMatchesReferenceMatcherOnFullKJV() async throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")

        let catalog = try await JSONBibleBookCatalog.load(
            from: resources.appendingPathComponent("kjv-books.json")
        )
        let repository = try await JSONBibleRepository.load(
            from: resources.appendingPathComponent("kjv-verses.json"),
            books: catalog.books
        )

        // Decode the file directly (cheaper than per-chapter repository
        // calls) and sort into canonical reading order.
        struct Row: Decodable {
            let book_id: String
            let chapter: Int
            let verse: Int
            let text: String
        }
        let rows = try JSONDecoder().decode(
            [Row].self,
            from: Data(contentsOf: resources.appendingPathComponent("kjv-verses.json"))
        )
        let order = Dictionary(
            uniqueKeysWithValues: catalog.books.map { ($0.bookID, $0.canonicalOrder) }
        )
        let all = try rows
            .sorted {
                ($0.book_id == $1.book_id)
                    ? ($0.chapter, $0.verse) < ($1.chapter, $1.verse)
                    : order[$0.book_id]! < order[$1.book_id]!
            }
            .map {
                try BibleVerse(
                    reference: BibleReference(
                        bookID: $0.book_id,
                        chapter: $0.chapter,
                        verse: $0.verse
                    ),
                    text: $0.text
                )
            }
        #expect(all.count == 31_102)

        // Tokenize once with the reference rules; queries reuse the words.
        let referenceWords = all.map { Self.referenceWords($0.text) }

        for raw in Self.queries {
            let terms = Self.referenceTerms(raw)
            let expected = zip(all, referenceWords).filter { _, words in
                terms.allSatisfy { Self.contains($0, in: words) }
            }.map(\.0)

            let actual: BibleTextSearchResult
            do {
                actual = try await repository.search(
                    BibleTextQuery(raw),
                    limit: Int.max
                )
            } catch BibleTextQuery.ParseError.tooShort {
                // "1" and "o" are below the two-letter minimum by design.
                continue
            }

            #expect(actual.verses == expected, "query \(raw)")
            #expect(actual.totalCount == expected.count, "query \(raw)")
        }
    }

    private static func referenceWords(_ text: String) -> [String] {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
    }

    private static func referenceTerms(_ raw: String) -> [[String]] {
        var terms: [[String]] = []
        let segments = raw.split(separator: "\"", omittingEmptySubsequences: false)
        for (index, segment) in segments.enumerated() {
            let words = referenceWords(String(segment))
            if index.isMultiple(of: 2) {
                terms += words.map { [$0] }
            } else if !words.isEmpty {
                terms.append(words)
            }
        }
        return terms
    }

    private static func contains(_ term: [String], in words: [String]) -> Bool {
        guard !term.isEmpty else { return true }
        guard words.count >= term.count else { return false }
        return (0...(words.count - term.count)).contains { start in
            words[start...].starts(with: term)
        }
    }
}
