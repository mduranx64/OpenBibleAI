//
//  GoldenRetrievalTests.swift
//  BibleData
//

import Foundation
import Testing
import BibleData
import BibleDomain

/// Retrieval quality on the real bundled KJV: for each question, at least one
/// expected passage must be among the passages an answer would be grounded
/// on. `keywords` stands in for the terms the model suggests; `question` is
/// the user's own words. Keyword-only retrieval cannot handle other languages,
/// so Spanish questions rely on model keywords (and later embeddings).
struct GoldenRetrievalTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let question: String
        let keywords: [String]
        /// "BOOK chapter:first-last" ranges; any overlap counts as found.
        let expected: [String]
        var testDescription: String { question }
    }

    static let cases: [Case] = [
        Case(question: "Where was Jesus born?",
             keywords: ["Jesus", "born", "Bethlehem", "Judaea", "manger"],
             expected: ["MAT 2:1-6", "LUK 2:4-7"]),
        Case(question: "Where did Jesus heal a blind person?",
             keywords: ["Jesus", "blind", "sight", "eyes", "opened", "healed"],
             expected: ["JOH 9:1-41", "MAR 10:46-52", "MAR 8:22-26", "MAT 9:27-30", "MAT 20:29-34", "LUK 18:35-43"]),
        Case(question: "What does the Bible say about forgiving others?",
             keywords: ["forgive", "trespasses", "brother", "seventy", "times"],
             expected: ["MAT 6:12-15", "MAT 18:21-35", "MAR 11:25-26", "LUK 17:3-4", "EPH 4:32-32", "COL 3:13-13"]),
        Case(question: "How did Jesus feed five thousand people?",
             keywords: ["five", "loaves", "two", "fishes", "thousand", "fed"],
             expected: ["MAT 14:15-21", "MAR 6:35-44", "LUK 9:12-17", "JOH 6:5-13"]),
        Case(question: "How did Moses cross the Red Sea?",
             keywords: ["Moses", "sea", "divided", "dry", "ground", "waters"],
             expected: ["EXO 14:16-29"]),
    ]

    private static let repository: JSONBibleRepository = {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources")
        let books = try! JSONBibleBookCatalog(data: Data(contentsOf: resources.appendingPathComponent("kjv-books.json"))).books
        return try! JSONBibleRepository(data: Data(contentsOf: resources.appendingPathComponent("kjv-verses.json")), books: books)
    }()

    private func found(_ passages: [BiblePassage], _ expected: [String]) -> Bool {
        expected.contains { range in
            let parts = range.split(separator: " ")
            let book = String(parts[0])
            let cv = parts[1].split(separator: ":")
            let chapter = Int(cv[0])!
            let bounds = cv[1].split(separator: "-").map { Int($0)! }
            return passages.contains { passage in
                passage.bookID == book && passage.chapter == chapter
                    && passage.verses.contains { (bounds[0]...bounds[1]).contains($0.reference.verse) }
            }
        }
    }

    private func retrieve(_ terms: [String]) async throws -> [BiblePassage] {
        let ranked = try await Self.repository.rankedVerses(matching: terms, limit: 20)
        return try await Self.repository.passages(
            around: ranked.map(\.reference), window: 2, limit: 6, characterBudget: 6_000
        )
    }

    @Test(arguments: cases)
    func modelStyleKeywordsRetrieveAnExpectedPassage(_ golden: Case) async throws {
        let passages = try await retrieve(golden.keywords + [golden.question])
        #expect(found(passages, golden.expected),
                "Got \(passages.map { "\($0.bookID) \($0.chapter):\($0.verses.first!.reference.verse)" })")
    }

    @Test
    func theUsersOwnWordsAloneFindTheTwoExampleQuestions() async throws {
        for golden in Self.cases.prefix(2) {
            let passages = try await retrieve([golden.question])
            #expect(found(passages, golden.expected), "\(golden.question)")
        }
    }
}
