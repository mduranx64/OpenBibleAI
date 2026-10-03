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

    public enum Testament: Hashable, Sendable, CaseIterable {
        case old
        case new
    }

    /// Derived from the publisher book ID: the 27 New Testament books are
    /// `.new`; every other book, including the deuterocanonical books of
    /// Catholic editions (in their place in the version's order), is `.old`.
    public var testament: Testament {
        Self.newTestamentIDs.contains(bookID) ? .new : .old
    }

    static let newTestamentIDs: Set<String> = [
        "MAT", "MAR", "LUK", "JOH", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH",
        "PHI", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAM",
        "1PE", "2PE", "1JO", "2JO", "3JO", "JUD", "REV",
    ]

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
