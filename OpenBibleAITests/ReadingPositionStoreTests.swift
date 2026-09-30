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
        let suiteName = "ReadingPositionStoreTests.\(UUID())"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
        let suiteName = "ReadingPositionStoreTests.\(UUID())"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ReadingPositionStore(defaults: defaults)

        let position = try store.load()

        #expect(position == nil)
    }
    
    @Test
    func savingNewPositionReplacesPreviousPosition() throws {
        let suiteName = "ReadingPositionStoreTests.\(UUID())"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
        let suiteName = "ReadingPositionStoreTests.\(UUID())"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
