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
    
    @Test func bibleReferenceRejectsChapterZero()  {
        #expect(
            throws: BibleReference.ValidationError.invalidChapter(0)
        ) {
            try BibleReference(bookID: "GEN", chapter: 0, verse: 1)
        }
    }
    
    @Test func bibleReferenceRejectsVerseZero() {
        #expect(
            throws: BibleReference.ValidationError.invalidVerse(0)
        ) {
            try BibleReference(bookID: "GEN", chapter: 1, verse: 0)
        }
    }
    
    @Test func bibleReferenceRejectsBookIDEmpty() {
        #expect(
            throws: BibleReference.ValidationError.emptyBookID
        ) {
           try BibleReference(bookID: "", chapter: 1, verse: 1)
        }
        
    }
}
