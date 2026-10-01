//
//  BibleStudyContextTests.swift
//  BibleAI
//

import Testing
import BibleAI
import BibleDomain

struct BibleStudyContextTests {
    private func verse(
        _ number: Int,
        chapter: Int = 3,
        book: String = "JOH",
        text: String? = nil
    ) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(
                bookID: book,
                chapter: chapter,
                verse: number
            ),
            text: text ?? "Verse \(number) text."
        )
    }

    private func reference(_ number: Int, chapter: Int = 3) throws -> BibleReference {
        try BibleReference(bookID: "JOH", chapter: chapter, verse: number)
    }

    private func numbers(_ verses: [BibleVerse]) -> [Int] {
        verses.map(\.reference.verse)
    }

    @Test
    func wholeChapterIsReturnedInOrderWhenItFitsTheLimit() throws {
        let chapter = try [5, 1, 3, 2, 4].map { try verse($0) }

        let window = BibleStudyContext.verses(
            in: chapter,
            around: try reference(3),
            characterLimit: 1_000
        )

        #expect(numbers(window) == [1, 2, 3, 4, 5])
    }

    @Test
    func longChapterIsTrimmedToAContiguousWindowAroundTheSelectedVerse() throws {
        // Each verse text is 10 characters; a 50-character budget fits 5.
        let chapter = try (1...20).map { try verse($0, text: String(repeating: "x", count: 10)) }

        let window = BibleStudyContext.verses(
            in: chapter,
            around: try reference(10),
            characterLimit: 50
        )

        #expect(numbers(window) == [8, 9, 10, 11, 12])
        #expect(window.reduce(0) { $0 + $1.text.count } <= 50)
    }

    @Test
    func windowStopsAtChapterEdgesAndSpendsTheRemainingBudgetOnTheOtherSide() throws {
        let chapter = try (1...20).map { try verse($0, text: String(repeating: "x", count: 10)) }

        let atStart = BibleStudyContext.verses(
            in: chapter,
            around: try reference(1),
            characterLimit: 50
        )
        let atEnd = BibleStudyContext.verses(
            in: chapter,
            around: try reference(20),
            characterLimit: 50
        )

        #expect(numbers(atStart) == [1, 2, 3, 4, 5])
        #expect(numbers(atEnd) == [16, 17, 18, 19, 20])
    }

    @Test
    func selectedVerseIsAlwaysIncludedEvenWhenItAloneExceedsTheLimit() throws {
        let chapter = try [
            verse(1),
            verse(2, text: String(repeating: "y", count: 500)),
            verse(3)
        ]

        let window = BibleStudyContext.verses(
            in: chapter,
            around: try reference(2),
            characterLimit: 100
        )

        #expect(numbers(window) == [2])
    }

    @Test
    func versesFromOtherChaptersAreIgnored() throws {
        let chapter = try [
            verse(1),
            verse(2),
            verse(1, chapter: 4),
            verse(1, book: "GEN")
        ]

        let window = BibleStudyContext.verses(
            in: chapter,
            around: try reference(1),
            characterLimit: 1_000
        )

        #expect(numbers(window) == [1, 2])
        #expect(window.allSatisfy { $0.reference.chapter == 3 && $0.reference.bookID == "JOH" })
    }

    @Test
    func missingSelectedVerseYieldsNoContext() throws {
        let chapter = try [verse(1), verse(2)]

        let window = BibleStudyContext.verses(
            in: chapter,
            around: try reference(9),
            characterLimit: 1_000
        )

        #expect(window.isEmpty)
    }

    @Test
    func defaultLimitMatchesTheDocumentedBound() {
        #expect(BibleStudyContext.defaultCharacterLimit == 6_000)
    }
}
