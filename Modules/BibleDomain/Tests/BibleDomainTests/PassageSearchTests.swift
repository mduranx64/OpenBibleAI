//
//  PassageSearchTests.swift
//  BibleDomain
//

import Testing
import BibleDomain

struct RankedVerseIndexTokenTests {
    @Test
    func tokensDropStopWordsAndStemKJVSuffixes() {
        #expect(RankedVerseIndex.tokens(in: "Where was Jesus born?") == ["jesus", "born"])
        #expect(RankedVerseIndex.tokens(in: "And he healed them; he healeth, healing") == ["heal", "heal", "heal"])
        #expect(RankedVerseIndex.tokens(in: "Unto thee the LORD saith") == ["lord"])
        #expect(RankedVerseIndex.tokens(in: "blind eyes") == ["blind", "eye"])
    }
}

struct PassageSearchTests {
    private func verse(_ book: String, _ chapter: Int, _ number: Int, _ text: String) throws -> BibleVerse {
        try BibleVerse(reference: BibleReference(bookID: book, chapter: chapter, verse: number), text: text)
    }

    private func repository() throws -> InMemoryBibleRepository {
        InMemoryBibleRepository(
            verses: [
                try verse("MAT", 2, 1, "Now when Jesus was born in Bethlehem of Judaea"),
                try verse("MAT", 2, 2, "Saying, Where is he that is born King of the Jews?"),
                try verse("MAT", 2, 3, "When Herod the king had heard these things, he was troubled"),
                try verse("MAT", 2, 4, "And when he had gathered all the chief priests"),
                try verse("MAT", 2, 5, "And they said unto him, In Bethlehem of Judaea"),
                try verse("MAT", 3, 1, "In those days came John the Baptist"),
                try verse("JOH", 9, 1, "And as Jesus passed by, he saw a man which was blind from his birth."),
                try verse("JOH", 9, 2, "And his disciples asked him"),
                try verse("JOH", 9, 7, "He went his way therefore, and washed, and came seeing.")
            ],
            books: [
                try BibleBook(bookID: "MAT", name: "Matthew", canonicalOrder: 40),
                try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)
            ]
        )
    }

    private func label(_ passage: BiblePassage) -> String {
        "\(passage.bookID) \(passage.chapter):\(passage.verses.first!.reference.verse)-\(passage.verses.last!.reference.verse)"
    }

    @Test
    func rankedVersesPutTheBestMatchFirst() async throws {
        let ranked = try await repository().rankedVerses(matching: ["jesus", "born", "bethlehem"], limit: 3)

        #expect(ranked.first?.reference == (try BibleReference(bookID: "MAT", chapter: 2, verse: 1)))
        #expect(ranked.count <= 3)
        #expect(ranked.map(\.score) == ranked.map(\.score).sorted(by: >))
    }

    @Test
    func noMatchingTermsReturnNothing() async throws {
        #expect(try await repository().rankedVerses(matching: ["zebra"], limit: 5).isEmpty)
        #expect(try await repository().rankedVerses(matching: ["the", "and"], limit: 5).isEmpty)
    }

    @Test
    func passagesExpandHitsWithinTheChapterAndMergeOverlaps() async throws {
        let repository = try repository()
        let hits = try [
            BibleReference(bookID: "MAT", chapter: 2, verse: 1),
            BibleReference(bookID: "MAT", chapter: 2, verse: 2),
            BibleReference(bookID: "JOH", chapter: 9, verse: 1)
        ]

        let passages = try await repository.passages(around: hits, window: 2, limit: 5, characterBudget: 10_000)

        // MAT 2:1 and 2:2 windows merge; nothing crosses into MAT 3.
        #expect(passages.map(label) == ["MAT 2:1-4", "JOH 9:1-2"])
    }

    @Test
    func passagesRespectLimitAndCharacterBudget() async throws {
        let repository = try repository()
        let hits = try [
            BibleReference(bookID: "MAT", chapter: 2, verse: 1),
            BibleReference(bookID: "JOH", chapter: 9, verse: 7)
        ]

        let limited = try await repository.passages(around: hits, window: 0, limit: 1, characterBudget: 10_000)
        #expect(limited.map(label) == ["MAT 2:1-1"])

        let budgeted = try await repository.passages(around: hits, window: 1, limit: 5, characterBudget: 120)
        #expect(budgeted.map(label) == ["MAT 2:1-2"])
    }
}
