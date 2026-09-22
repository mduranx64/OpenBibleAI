//
//  BibleReference.swift
//  BibleDomain
//
//  Created by Miguel Duran on 21-09-26.
//

public struct BibleReference: Hashable, Sendable {
    public let bookID: String
    public let chapter: Int
    public let verse: Int
    
    public init(bookID: String, chapter: Int, verse: Int) {
        self.bookID = bookID
        self.chapter = chapter
        self.verse = verse
    }
}
