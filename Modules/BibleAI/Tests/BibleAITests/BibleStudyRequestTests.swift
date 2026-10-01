//
//  BibleStudyRequestTests.swift
//  BibleAI
//

import Testing
import BibleAI
import BibleDomain

struct BibleStudyRequestTests {
    private func verse(_ number: Int, chapter: Int = 3, book: String = "JOH") throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(bookID: book, chapter: chapter, verse: number),
            text: "Verse \(number)."
        )
    }

    @Test
    func requestWithoutContextKeepsExistingBehavior() throws {
        let request = try BibleStudyRequest(
            verse: verse(16),
            question: "  What does this mean?  "
        )

        #expect(request.question == "What does this mean?")
        #expect(request.context.isEmpty)
        #expect(request.bookName == nil)
    }

    @Test
    func requestStoresBookNameAndContext() throws {
        let request = try BibleStudyRequest(
            verse: verse(16),
            bookName: "John",
            context: [verse(15), verse(16), verse(17)],
            question: "Why?"
        )

        #expect(request.bookName == "John")
        #expect(request.context.map(\.reference.verse) == [15, 16, 17])
    }

    @Test(arguments: [(4, "JOH"), (3, "GEN")])
    func contextFromAnotherChapterOrBookIsRejected(chapter: Int, book: String) throws {
        let selected = try verse(16)
        let foreign = try verse(1, chapter: chapter, book: book)

        #expect(throws: BibleStudyRequest.ValidationError.contextOutsideChapter) {
            try BibleStudyRequest(
                verse: selected,
                context: [foreign],
                question: "Why?"
            )
        }
    }

    @Test
    func blankBookNameIsTreatedAsMissing() throws {
        let request = try BibleStudyRequest(
            verse: verse(16),
            bookName: "   ",
            question: "Why?"
        )

        #expect(request.bookName == nil)
    }
}
