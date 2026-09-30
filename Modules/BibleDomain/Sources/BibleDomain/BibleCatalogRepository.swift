//
//  BibleCatalogRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 29-09-26.
//

public protocol BibleCatalogRepository: Sendable {
    func books() async throws -> [BibleBook]

    func chapters(in bookID: String) async throws -> [Int]

    func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse]
}
