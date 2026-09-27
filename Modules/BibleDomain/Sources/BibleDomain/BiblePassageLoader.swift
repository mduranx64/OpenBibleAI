//
//  BiblePassageLoader.swift
//  BibleDomain
//
//  Created by Miguel Duran on 27-09-26.
//

public struct BiblePassageLoader: Sendable {
    private let repository: any BibleRepository

    public init(repository: any BibleRepository) {
        self.repository = repository
    }

    public func verses(
        at references: [BibleReference]
    ) async throws -> [BibleVerse] {
        try await withThrowingTaskGroup(
            of: (index: Int, verse: BibleVerse).self
        ) { group in
            for (index, reference) in references.enumerated() {
                group.addTask { [repository] in
                    let verse = try await repository.verse(
                        at: reference
                    )

                    return (index, verse)
                }
            }

            var completedVerses: [
                (index: Int, verse: BibleVerse)
            ] = []

            completedVerses.reserveCapacity(references.count)

            for try await completedVerse in group {
                completedVerses.append(completedVerse)
            }

            return completedVerses
                .sorted { $0.index < $1.index }
                .map { $0.verse }
        }
    }
}
