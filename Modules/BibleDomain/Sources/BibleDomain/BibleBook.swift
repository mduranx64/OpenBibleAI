//
//  BibleBook.swift
//  BibleDomain
//
//  Created by Miguel Duran on 29-09-26.
//

import Foundation

public struct BibleBook:
    Identifiable,
    Hashable,
    Sendable
{
    public var id: String {
        bookID
    }

    public let bookID: String
    public let name: String
    public let canonicalOrder: Int

    public init(
        bookID: String,
        name: String,
        canonicalOrder: Int
    ) throws(ValidationError) {
        guard !bookID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw .blankBookID
        }

        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw .blankName
        }

        guard canonicalOrder > 0 else {
            throw .invalidCanonicalOrder(
                canonicalOrder
            )
        }

        self.bookID = bookID
        self.name = name
        self.canonicalOrder = canonicalOrder
    }

    public enum ValidationError:
        Error,
        Equatable,
        Sendable
    {
        case blankBookID
        case blankName
        case invalidCanonicalOrder(Int)
    }
}
