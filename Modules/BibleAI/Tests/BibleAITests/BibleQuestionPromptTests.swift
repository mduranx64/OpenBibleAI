//
//  BibleQuestionPromptTests.swift
//  BibleAI
//

import Testing
import BibleDomain

@testable import BibleAI

struct SearchKeywordParserTests {
    @Test
    func parsesCommaAndLineSeparatedKeywordsAndDropsNoise() {
        #expect(SearchKeywordParser.keywords(from: "born, Bethlehem, Judaea, manger") == ["born", "Bethlehem", "Judaea", "manger"])
        #expect(SearchKeywordParser.keywords(from: "1. blind\n2. sight\n- eyes opened\n* \"healed\".") == ["blind", "sight", "eyes", "opened", "healed"])
        #expect(SearchKeywordParser.keywords(from: "Keywords: forgive; Forgive; trespasses") == ["forgive", "trespasses"])
        #expect(SearchKeywordParser.keywords(from: "") == [])
    }

    @Test
    func keepsAtMostTwelveKeywords() {
        // Digits are dropped by design (KJV spells numbers out), so use letters.
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let many = letters.map { "word\($0)" }.joined(separator: ", ")
        #expect(SearchKeywordParser.keywords(from: many).count == 12)
    }
}

struct BibleQuestionPromptTests {
    private func passage() throws -> BibleQuestionPrompt.Passage {
        let verses = try [1, 2].map {
            try BibleVerse(reference: BibleReference(bookID: "MAT", chapter: 2, verse: $0), text: "Verse \($0) text.")
        }
        return BibleQuestionPrompt.Passage(
            bookName: "Matthew",
            passage: BiblePassage(bookID: "MAT", chapter: 2, verses: verses)
        )
    }

    @Test
    func keywordPromptAsksForEnglishKJVWordsForAnyLanguage() {
        let prompt = BibleQuestionPrompt.keywords(for: "¿Dónde nació Jesús?")

        #expect(prompt.user.contains("¿Dónde nació Jesús?"))
        #expect(prompt.system.contains("English"))
        #expect(prompt.system.contains("King James"))
        #expect(prompt.system.contains("comma"))
        #expect(prompt.isContentTransformation, "Keyword extraction transforms the user's text")
        #expect(prompt.system.contains("main subject"))
    }

    @Test
    func answerPromptListsEveryVerseWithItsFullReferenceAndCitationRules() throws {
        let prompt = BibleQuestionPrompt.answer(question: "Where was Jesus born?", passages: [try passage()])

        #expect(prompt.user.contains("Matthew 2:1 Verse 1 text."))
        #expect(prompt.user.contains("Matthew 2:2 Verse 2 text."))
        #expect(prompt.user.contains("Question:\nWhere was Jesus born?"))
        #expect(prompt.system.contains("[Matthew 2:1]"))
        #expect(prompt.system.contains("only"))
        #expect(prompt.system.contains("same language as the question"))
        #expect(prompt.system.contains("Do not quote or translate"))
        #expect(!prompt.isContentTransformation)
    }

    @Test
    func answerPromptNamesTheQuestionsLanguageAndRepeatsTheNoQuotingRule() throws {
        let spanish = BibleQuestionPrompt.answer(question: "¿Dónde nació Jesús? ¿En qué ciudad nació el Señor?", passages: [try passage()])
        #expect(spanish.user.hasSuffix("Write your answer in Spanish. Cite verses in brackets with the English book names shown, like [Matthew 2:1]. Summarize the verses; do not quote or translate them."))

        let english = BibleQuestionPrompt.answer(question: "Where was Jesus born, and in which town?", passages: [try passage()])
        #expect(english.user.hasSuffix("Write your answer in English. Cite verses in brackets with the English book names shown, like [Matthew 2:1]. Summarize the verses; do not quote or translate them."))
    }

    @Test
    func answerPromptIncludesRecentHistoryBeforeThePassagesAndKeepsItOutOfCitations() throws {
        let history = [
            BibleQuestionPrompt.Turn(question: "Who was Moses?", answer: "A prophet [Exodus 3:10]."),
            BibleQuestionPrompt.Turn(question: "Where was Jesus born?", answer: "In Bethlehem [Matthew 2:1].")
        ]
        let prompt = BibleQuestionPrompt.answer(question: "Who visited him?", passages: [try passage()], history: history)

        let earlier = try #require(prompt.user.range(of: "Earlier conversation:"))
        let passages = try #require(prompt.user.range(of: "Passages (King James Version):"))
        #expect(earlier.lowerBound < passages.lowerBound)
        #expect(prompt.user.contains("User: Where was Jesus born?\nAssistant: In Bethlehem [Matthew 2:1]."))
        #expect(prompt.system.contains("do not cite it"))
    }

    @Test
    func historyIsTrimmedOldestFirstToTheCharacterLimit() {
        let turns = (1...4).map { BibleQuestionPrompt.Turn(question: "Q\($0)", answer: String(repeating: "a", count: 8)) }
        // Each turn is 10 characters: a limit of 25 keeps the last two.
        let kept = BibleQuestionPrompt.trimmedHistory(turns, characterLimit: 25)
        #expect(kept.map(\.question) == ["Q3", "Q4"])

        let tooLong = [BibleQuestionPrompt.Turn(question: "Q", answer: String(repeating: "a", count: 50))]
        #expect(BibleQuestionPrompt.trimmedHistory(tooLong, characterLimit: 25).isEmpty)

        let prompt = BibleQuestionPrompt.answer(question: "Q?", passages: [], history: turns, historyCharacterLimit: 25)
        #expect(!prompt.user.contains("Q2"))
        #expect(prompt.user.contains("User: Q4"))
    }

    @Test
    func answerPromptShowsTheAttachedVerseWithItsChapterContext() throws {
        let verses = try [15, 16, 17].map {
            try BibleVerse(reference: BibleReference(bookID: "JHN", chapter: 3, verse: $0), text: "John \($0).")
        }
        let focus = BibleQuestionPrompt.FocusVerse(bookName: "John", verse: verses[1], context: verses)
        let prompt = BibleQuestionPrompt.answer(question: "What does this mean?", passages: [], focus: focus)

        #expect(prompt.user.contains("The user is asking about John 3:16:\nJohn 3:15 John 15.\nJohn 3:16 John 16.\nJohn 3:17 John 17."))
    }

    @Test
    func keywordPromptGetsThePreviousTurnAndAttachedVerseForFollowUps() throws {
        let plain = BibleQuestionPrompt.keywords(for: "And where did he die?")
        #expect(plain.user == "And where did he die?")

        let verse = try BibleVerse(reference: BibleReference(bookID: "JHN", chapter: 3, verse: 16), text: "For God so loved the world")
        let prompt = BibleQuestionPrompt.keywords(
            for: "And where did he die?",
            previous: .init(question: "Where was Jesus born?", answer: "In Bethlehem " + String(repeating: "x", count: 500)),
            focus: .init(bookName: "John", verse: verse, context: [])
        )
        let shortened = "In Bethlehem " + String(repeating: "x", count: 400 - 13)
        #expect(prompt.user == "Previous question: Where was Jesus born?\nPrevious answer: \(shortened)\nAbout the verse: John 3:16 For God so loved the world\nQuestion: And where did he die?")
        #expect(prompt.system.contains("previous answer"))
    }

    @Test
    func answerPromptWithoutPassagesSaysNothingWasFound() {
        let prompt = BibleQuestionPrompt.answer(question: "Q?", passages: [])
        #expect(prompt.user.contains("No passages were found"))
    }
}
