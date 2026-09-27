//
//  JSONBibleRepository.swift
//  BibleData
//
//  Created by Miguel Duran on 27-09-26.
//

import Foundation
import BibleDomain

public struct JSONBibleRepository: BibleRepository {
    private let base: InMemoryBibleRepository

    public init(data: Data) throws {
        let decoder = JSONDecoder()

        let verseDTOs = try decoder.decode(
            [BibleVerseDTO].self,
            from: data
        )

        let verses = try verseDTOs.map {
            try $0.domainModel()
        }

        var seenReferences: Set<BibleReference> = []

        for verse in verses {
            let insertion = seenReferences.insert(
                verse.reference
            )

            guard insertion.inserted else {
                throw LoadError.duplicateReference(
                    verse.reference
                )
            }
        }

        self.base = InMemoryBibleRepository(
            verses: verses
        )
    }

    public func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        try await base.verse(at: reference)
    }
    
    public enum LoadError: Error, Equatable, Sendable {
        case duplicateReference(BibleReference)
    }
}
