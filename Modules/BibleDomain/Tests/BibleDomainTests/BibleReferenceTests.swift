//
//  BibleReferenceTests.swift
//  BibleDomain
//
//  Created by Miguel Duran on 22-09-26.
//

import Testing
import BibleDomain

struct BibleReferenceTests {
    @Test func bibleReferenceStoresItsLocation() throws {
        let reference = try BibleReference(bookID: "GEN", chapter: 1, verse: 1)
        
        #expect(reference.bookID == "GEN")
        #expect(reference.verse == 1)
        #expect(reference.chapter == 1)
    }
    
    @Test(arguments: [0, -1])
    func bibleReferenceRejectsInvalidChapter(_ chapter: Int) {
        #expect(
            throws: BibleReference.ValidationError.invalidChapter(chapter)
        ) {
            try BibleReference(
                bookID: "GEN",
                chapter: chapter,
                verse: 1
            )
        }
    }
    
    @Test(arguments: [0, -1])
    func bibleReferenceRejectsVerseZero(_ verse: Int) {
        #expect(
            throws: BibleReference.ValidationError.invalidVerse(verse)
        ) {
            try BibleReference(bookID: "GEN", chapter: 1, verse: verse)
        }
    }
    
    @Test(arguments: ["", " ", "\n", "\t"])
    func bibleReferenceRejectsBlankBookID(_ bookID: String) {
        #expect(
            throws: BibleReference.ValidationError.blankBookID
        ) {
           try BibleReference(bookID: bookID, chapter: 1, verse: 1)
        }
        
    }
}
