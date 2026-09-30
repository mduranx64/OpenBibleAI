//
//  ReadingPositionStoreTests.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 30-09-26.
//

import Foundation
import Testing
@testable import OpenBibleAI

@Suite
@MainActor
struct ReadingPositionStoreTests {
    @Test
    func savedPositionCanBeLoadedByAnotherStore() throws {
        let defaults = InMemoryReadingPositionStorage()

        let expectedPosition = try ReadingPosition(
            bookID: "GEN",
            chapter: 3
        )

        let store = ReadingPositionStore(defaults: defaults)
        try store.save(expectedPosition)

        let reopenedStore = ReadingPositionStore(
            defaults: defaults
        )

        let restoredPosition = try reopenedStore.load()

        #expect(restoredPosition == expectedPosition)
    }

    @Test
    func loadReturnsNilWhenNoPositionHasBeenSaved() throws {
        let defaults = InMemoryReadingPositionStorage()

        let store = ReadingPositionStore(defaults: defaults)

        let position = try store.load()

        #expect(position == nil)
    }

    @Test
    func savingNewPositionReplacesPreviousPosition() throws {
        let defaults = InMemoryReadingPositionStorage()

        let store = ReadingPositionStore(defaults: defaults)

        let initialPosition = try ReadingPosition(
            bookID: "GEN",
            chapter: 3
        )

        let latestPosition = try ReadingPosition(
            bookID: "JOH",
            chapter: 16
        )

        try store.save(initialPosition)
        try store.save(latestPosition)

        let reopenedStore = ReadingPositionStore(defaults: defaults)
        let restoredPosition = try reopenedStore.load()

        #expect(restoredPosition == latestPosition)
    }

    @Test
    func loadRejectsSavedPositionWithInvalidChapter() throws {
        let defaults = InMemoryReadingPositionStorage()

        let json = """
        {
            "bookID": "GEN",
            "chapter": 0
        }
        """

        defaults.set(
            Data(json.utf8),
            forKey: "bible.readingPosition"
        )

        let store = ReadingPositionStore(defaults: defaults)

        #expect(
            throws: ReadingPosition.ValidationError.invalidChapter(0)
        ) {
            try store.load()
        }
    }
}

/// An in-memory `ReadingPositionStorage` so tests don't touch the real
/// `UserDefaults` or leave suite files behind on disk.
private final class InMemoryReadingPositionStorage: ReadingPositionStorage {
    private var storage: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}
