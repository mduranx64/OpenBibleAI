//
//  BibleVerse.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public struct BibleVerse: Hashable, Sendable {
    public let reference: BibleReference
    public let text: String

    public init(
        reference: BibleReference,
        text: String
    ) throws(ValidationError){
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw .blankText
        }
        
        self.reference = reference
        self.text = text
    }
    
    public enum ValidationError: Error, Equatable, Sendable {
            case blankText
        }
}
