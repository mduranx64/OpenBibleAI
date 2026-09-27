//
//  BibleVerseTests.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

import Testing
import BibleDomain

struct BibleVerseTests {
    @Test
    func bibleVerseStoresReferenceAndText() throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        let verse = try BibleVerse(
            reference: reference,
            text: "In the beginning God created the heavens and the earth."
        )

        #expect(verse.reference == reference)
        #expect(
            verse.text ==
            "In the beginning God created the heavens and the earth."
        )
    }
    
    @Test(arguments: ["", " ", "\n", "\t"])
    func bibleVerseRejectsBlankText(_ text: String) throws {
        let reference = try BibleReference(
            bookID: "GEN",
            chapter: 1,
            verse: 1
        )

        #expect(
            throws: BibleVerse.ValidationError.blankText
        ) {
            try BibleVerse(
                reference: reference,
                text: text
            )
        }
    }
}
