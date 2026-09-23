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
    
    public init(
        bookID: String,
        chapter: Int,
        verse: Int
    ) throws(ValidationError) {
        guard chapter > 0 else {
            throw .invalidChapter(chapter)
        }
        
        guard verse > 0 else {
            throw .invalidVerse(verse)
        }
        
        guard !bookID.isEmpty else {
            throw .emptyBookID
        }
        self.bookID = bookID
        self.chapter = chapter
        self.verse = verse
    }
    
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyBookID
        case invalidChapter(Int)
        case invalidVerse(Int)
    }
}
