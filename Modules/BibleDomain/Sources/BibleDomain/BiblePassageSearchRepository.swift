//
//  BiblePassageSearchRepository.swift
//  BibleDomain
//

/// Consecutive verses from one chapter, used as grounding for an answer.
public struct BiblePassage: Equatable, Sendable {
    public let bookID: String
    public let chapter: Int
    public let verses: [BibleVerse]

    public init(bookID: String, chapter: Int, verses: [BibleVerse]) {
        self.bookID = bookID
        self.chapter = chapter
        self.verses = verses
    }

    public var characterCount: Int {
        verses.reduce(0) { $0 + $1.text.count }
    }
}

/// Ranked retrieval for questions about the whole Bible. Separate from
/// verse lookup, catalog browsing and exact text search.
public protocol BiblePassageSearchRepository: Sendable {
    /// Verses ranked by keyword relevance to `terms`.
    func rankedVerses(matching terms: [String], limit: Int) async throws -> [RankedVerse]

    /// Passages around `references` (in priority order): each hit grows by
    /// `window` verses within its chapter, overlapping or adjacent passages
    /// merge, and passages stop at `limit` or once `characterBudget` would be
    /// exceeded (the first passage is always kept).
    func passages(
        around references: [BibleReference],
        window: Int,
        limit: Int,
        characterBudget: Int
    ) async throws -> [BiblePassage]
}
