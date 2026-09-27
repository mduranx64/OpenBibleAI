//
//  BibleRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public protocol BibleRepository: Sendable {
    func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse
}
