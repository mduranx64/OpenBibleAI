//
//  JSONBibleRepository.swift
//  BibleData
//
//  Created by Miguel Duran on 27-09-26.
//

import Foundation
import BibleDomain

public struct JSONBibleRepository: BibleRepository, BibleCatalogRepository {
    private let base: InMemoryBibleRepository

    public init(
        data: Data,
        books: [BibleBook] = []
    ) throws {
        let decoder = JSONDecoder()

        let verseDTOs = try decoder.decode(
            [BibleVerseDTO].self,
            from: data
        )

        let verses = try verseDTOs.map {
            try $0.domainModel()
        }

        var seenReferences: Set<BibleReference> = []

        for verse in verses {
            let insertion = seenReferences.insert(
                verse.reference
            )

            guard insertion.inserted else {
                throw LoadError.duplicateReference(
                    verse.reference
                )
            }
        }

        self.base = InMemoryBibleRepository(
            verses: verses,
            books: books
        )
    }

    public func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        try await base.verse(at: reference)
    }
    
    public func books() async throws -> [BibleBook] {
        try await base.books()
    }

    public func chapters(in bookID: String) async throws -> [Int] {
        try await base.chapters(in: bookID)
    }

    public func verses(
        in bookID: String,
        chapter: Int
    ) async throws -> [BibleVerse] {
        try await base.verses(
            in: bookID,
            chapter: chapter
        )
    }
    
    public enum LoadError: Error, Equatable, Sendable {
        case duplicateReference(BibleReference)
    }
    
    @concurrent
    public static func load(
        from fileURL: URL,
        books: [BibleBook] = []
    ) async throws -> Self {
        try Task.checkCancellation()

        let data = try Data(
            contentsOf: fileURL,
            options: .mappedIfSafe
        )

        try Task.checkCancellation()

        let repository = try Self(
            data: data,
            books: books
        )

        try Task.checkCancellation()

        return repository
    }
}
