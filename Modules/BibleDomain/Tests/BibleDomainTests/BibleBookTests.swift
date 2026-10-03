//
//  BibleBookTests.swift
//  BibleDomain
//
//  Created by Miguel Duran on 29-09-26.
//

import Testing
import BibleDomain

@Suite
struct BibleBookTests {
    @Test
    func storesBookIdentityAndCanonicalOrder() throws {
        let book = try BibleBook(
            bookID: "GEN",
            name: "Genesis",
            canonicalOrder: 1
        )

        #expect(book.bookID == "GEN")
        #expect(book.name == "Genesis")
        #expect(book.canonicalOrder == 1)
        #expect(book.id == "GEN")
    }
    
    @Test(arguments: [
        ("GEN", 1, BibleBook.Testament.old),
        ("MAL", 39, .old),
        ("MAT", 40, .new),
        ("REV", 66, .new),
        // A Catholic edition: deuterocanonical books in the Old Testament,
        // so the New Testament starts later in canonical order.
        ("TOB", 17, .old),
        ("2MA", 46, .old),
        ("MAT", 47, .new)
    ])
    func testamentFollowsTheBookID(id: String, order: Int, expected: BibleBook.Testament) throws {
        let book = try BibleBook(bookID: id, name: "Book \(order)", canonicalOrder: order)

        #expect(book.testament == expected)
    }

    @Test(arguments: ["", " ", "\n\t"])
    func rejectsBlankBookID(_ bookID: String) {
        #expect(throws: BibleBook.ValidationError.blankBookID) {
            try BibleBook(
                bookID: bookID,
                name: "Genesis",
                canonicalOrder: 1
            )
        }
    }

    @Test(arguments: ["", " ", "\n\t"])
    func rejectsBlankName(_ name: String) {
        #expect(throws: BibleBook.ValidationError.blankName) {
            try BibleBook(
                bookID: "GEN",
                name: name,
                canonicalOrder: 1
            )
        }
    }

    @Test(arguments: [0, -1])
    func rejectsInvalidCanonicalOrder(_ order: Int) {
        #expect(
            throws: BibleBook.ValidationError.invalidCanonicalOrder(order)
        ) {
            try BibleBook(
                bookID: "GEN",
                name: "Genesis",
                canonicalOrder: order
            )
        }
    }
}
