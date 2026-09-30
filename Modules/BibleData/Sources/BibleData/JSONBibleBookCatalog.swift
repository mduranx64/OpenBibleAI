//
//  JSONBibleBookCatalog.swift
//  BibleData
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation
import BibleDomain

public struct JSONBibleBookCatalog: Sendable {
    public let books: [BibleBook]

    public init(data: Data) throws {
        let bookDTOs = try JSONDecoder().decode(
            [BookDTO].self,
            from: data
        )

        let books = try bookDTOs.map { dto in
            try BibleBook(
                bookID: dto.bookID,
                name: dto.name,
                canonicalOrder: dto.canonicalOrder
            )
        }

        var seenBookIDs: Set<String> = []

        for book in books {
            guard seenBookIDs.insert(book.bookID).inserted else {
                throw LoadError.duplicateBookID(book.bookID)
            }
        }

        self.books = books
    }
    
    @concurrent
    public static func load(
        from fileURL: URL
    ) async throws -> Self {
        try Task.checkCancellation()

        let data = try Data(
            contentsOf: fileURL,
            options: .mappedIfSafe
        )

        try Task.checkCancellation()

        let catalog = try Self(data: data)

        try Task.checkCancellation()

        return catalog
    }

    public enum LoadError: Error, Equatable, Sendable {
        case duplicateBookID(String)
    }
}

private struct BookDTO: Decodable {
    let bookID: String
    let name: String
    let canonicalOrder: Int

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id"
        case name
        case canonicalOrder = "canonical_order"
    }
}
