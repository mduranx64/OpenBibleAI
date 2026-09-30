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
