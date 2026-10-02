//
//  BibleStudyPromptTests.swift
//  BibleAI
//

import Testing
import BibleDomain

@testable import BibleAI

/// The prompt every engine (Apple, MLX) receives for a study request.
struct BibleStudyPromptTests {
    private func verse(_ number: Int) throws -> BibleVerse {
        try BibleVerse(
            reference: BibleReference(bookID: "JOH", chapter: 3, verse: number),
            text: "Text of verse \(number)."
        )
    }

    @Test
    func userPromptUsesFullBookNameAndMarksTheSelectedVerseWithinContext() throws {
        let prompt = BibleStudyPrompt(
            try BibleStudyRequest(
                verse: verse(16),
                bookName: "John",
                context: [verse(15), verse(16), verse(17)],
                question: "What is the main idea?"
            )
        )

        #expect(prompt.user.contains("Passage: John 3:16"))
        #expect(!prompt.user.contains("JOH"))
        #expect(prompt.user.contains("Selected verse:\nText of verse 16."))
        #expect(prompt.user.contains("Chapter context"))
        #expect(prompt.user.contains("[15] Text of verse 15."))
        #expect(prompt.user.contains("> [16] Text of verse 16."))
        #expect(prompt.user.contains("[17] Text of verse 17."))
        #expect(prompt.user.hasSuffix("Question:\nWhat is the main idea?"))
    }

    @Test
    func userPromptWithoutContextOmitsTheContextSectionAndFallsBackToBookID() throws {
        let prompt = BibleStudyPrompt(
            try BibleStudyRequest(verse: verse(16), question: "Why?")
        )

        #expect(prompt.user.contains("Passage: JOH 3:16"))
        #expect(!prompt.user.contains("Chapter context"))
    }

    @Test
    func systemPromptSeparatesScriptureFromInterpretationAndForbidsInventedCitations() throws {
        let prompt = BibleStudyPrompt(
            try BibleStudyRequest(verse: verse(16), question: "Why?")
        )

        #expect(prompt.system.contains("Do not invent Scripture citations"))
        #expect(prompt.system.contains("context"))
        #expect(prompt.system.lowercased().contains("interpretation"))
    }
}
