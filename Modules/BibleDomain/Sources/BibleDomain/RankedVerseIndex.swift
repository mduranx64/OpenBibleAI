//
//  RankedVerseIndex.swift
//  BibleDomain
//

import Foundation

/// A verse and its relevance score for a query (higher is better).
public struct RankedVerse: Equatable, Sendable {
    public let reference: BibleReference
    public let score: Double

    public init(reference: BibleReference, score: Double) {
        self.reference = reference
        self.score = score
    }
}

/// BM25 keyword ranking over verses, tokenized by a language's
/// `TextAnalyzer` (in English, "healed", "healeth" and "healing" match "heal").
public struct RankedVerseIndex: Sendable {
    private struct Posting: Sendable {
        let verse: Int32
        let count: UInt16
    }

    private let references: [BibleReference]
    private let lengths: [Int]
    private let averageLength: Double
    private let postings: [String: [Posting]]
    private let analyzer: TextAnalyzer

    private static let k1 = 1.2
    private static let b = 0.75

    /// `verses` should be in reading order; ties keep that order.
    public init(verses: [BibleVerse], analyzer: TextAnalyzer = .english) {
        var postings: [String: [Posting]] = [:]
        var lengths: [Int] = []
        lengths.reserveCapacity(verses.count)

        for (index, verse) in verses.enumerated() {
            let tokens = analyzer.tokens(in: verse.text)
            lengths.append(tokens.count)
            var counts: [String: Int] = [:]
            for token in tokens { counts[token, default: 0] += 1 }
            for (token, count) in counts {
                postings[token, default: []].append(
                    Posting(verse: Int32(index), count: UInt16(min(count, Int(UInt16.max))))
                )
            }
        }

        self.references = verses.map(\.reference)
        self.lengths = lengths
        self.averageLength = lengths.isEmpty ? 1 : Double(lengths.reduce(0, +)) / Double(lengths.count)
        self.postings = postings
        self.analyzer = analyzer
    }

    /// Ranks verses for the given terms (free text; tokenized like verses).
    public func search(terms: [String], limit: Int) -> [RankedVerse] {
        let queryTokens = Set(terms.flatMap(analyzer.tokens(in:)))
        guard !queryTokens.isEmpty, limit > 0 else { return [] }

        let count = Double(references.count)
        var scores: [Int32: Double] = [:]

        for token in queryTokens {
            guard let list = postings[token] else { continue }
            let frequency = Double(list.count)
            let idf = log(1 + (count - frequency + 0.5) / (frequency + 0.5))
            for posting in list {
                let tf = Double(posting.count)
                let length = Double(lengths[Int(posting.verse)])
                let norm = tf * (Self.k1 + 1)
                    / (tf + Self.k1 * (1 - Self.b + Self.b * length / averageLength))
                scores[posting.verse, default: 0] += idf * norm
            }
        }

        return scores
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { RankedVerse(reference: references[Int($0.key)], score: $0.value) }
    }

    // MARK: - Tokens

    /// English (KJV) tokens; see `TextAnalyzer.english`.
    public static func tokens(in text: String) -> [String] {
        TextAnalyzer.english.tokens(in: text)
    }
}
