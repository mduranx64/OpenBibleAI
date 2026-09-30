//
//  ReadingPositionStore.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 30-09-26.
//

import Foundation

@MainActor
final class ReadingPositionStore {
    private static let storageKey = "bible.readingPosition"

    private let defaults: any ReadingPositionStorage

    init(defaults: any ReadingPositionStorage) {
        self.defaults = defaults
    }

    func save(_ position: ReadingPosition) throws {
        let data = try JSONEncoder().encode(position)

        defaults.set(
            data,
            forKey: Self.storageKey
        )
    }

    func load() throws -> ReadingPosition? {
        guard let data = defaults.data(
            forKey: Self.storageKey
        ) else {
            return nil
        }

        return try JSONDecoder().decode(
            ReadingPosition.self,
            from: data
        )
    }
}
