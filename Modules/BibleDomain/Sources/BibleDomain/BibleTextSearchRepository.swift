//
//  BibleTextSearchRepository.swift
//  BibleDomain
//

public struct BibleTextSearchResult: Equatable, Sendable {
    /// Matching verses in canonical order, at most the requested limit.
    public let verses: [BibleVerse]
    /// Every match found, including those beyond the limit.
    public let totalCount: Int

    public var isTruncated: Bool {
        totalCount > verses.count
    }

    public init(verses: [BibleVerse], totalCount: Int) {
        self.verses = verses
        self.totalCount = totalCount
    }
}

public protocol BibleTextSearchRepository: Sendable {
    func search(
        _ query: BibleTextQuery,
        limit: Int
    ) async throws -> BibleTextSearchResult
}
