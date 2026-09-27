//
//  CachingBibleRepository.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public actor CachingBibleRepository: BibleRepository {
    private let base: any BibleRepository
    private var cachedVerses: [
        BibleReference: BibleVerse
    ] = [:]
    private var inFlightRequests: [
        BibleReference: Task<BibleVerse, any Error>
    ] = [:]
    
    public init(base: any BibleRepository) {
        self.base = base
    }

    public func verse(
        at reference: BibleReference
    ) async throws -> BibleVerse {
        if let cachedVerse = cachedVerses[reference] {
            return cachedVerse
        }

        if let existingTask = inFlightRequests[reference] {
            return try await existingTask.value
        }

        let loadingTask = Task { [base] in
            try await base.verse(at: reference)
        }

        inFlightRequests[reference] = loadingTask

        defer {
            inFlightRequests[reference] = nil
        }

        let loadedVerse = try await loadingTask.value

        cachedVerses[reference] = loadedVerse

        return loadedVerse
    }
}
