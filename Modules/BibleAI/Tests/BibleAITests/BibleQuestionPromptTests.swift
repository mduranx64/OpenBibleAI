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
    func summaryPromptFoldsDroppedTurnsIntoThePreviousSummary() {
        let turns = [BibleQuestionPrompt.Turn(question: "Who was Herod?", answer: "The king [Matthew 2:1].")]
        let prompt = BibleQuestionPrompt.summary(of: turns, previousSummary: "They discussed Jesus' birth.")

        #expect(prompt.user == "Summary so far:\nThey discussed Jesus' birth.\n\nConversation to add:\nUser: Who was Herod?\nAssistant: The king [Matthew 2:1].")
        #expect(prompt.system.contains("language of the conversation"))
        #expect(prompt.system.contains("verse references"))
        #expect(prompt.isContentTransformation)

        let first = BibleQuestionPrompt.summary(of: turns, previousSummary: nil, characterLimit: 250)
        #expect(first.user.hasPrefix("Conversation to add:"))
        #expect(first.system.contains("under 250 characters"))
    }

    @Test
    func longSummariesAreCutAtTheLastSentenceThatFits() {
        #expect(BibleQuestionPrompt.trimmedSummary("  Short.  ", characterLimit: 20) == "Short.")
        #expect(BibleQuestionPrompt.trimmedSummary("One two. Three four five six.", characterLimit: 20) == "One two.")
        #expect(BibleQuestionPrompt.trimmedSummary("No sentence end at all here", characterLimit: 10) == "No sentenc")
    }

    @Test
    func answerPromptPutsTheSummaryBeforeRecentTurns() throws {
        let prompt = BibleQuestionPrompt.answer(
            question: "And then?",
            passages: [],
            history: [.init(question: "Recent?", answer: "Yes.")],
            summary: "Earlier they asked about Moses."
        )
        let summary = try #require(prompt.user.range(of: "Summary of earlier conversation:\nEarlier they asked about Moses."))
        let recent = try #require(prompt.user.range(of: "Earlier conversation:\nUser: Recent?"))
        #expect(summary.lowerBound < recent.lowerBound)
        #expect(!BibleQuestionPrompt.answer(question: "Q?", passages: []).user.contains("Summary of earlier"))
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
    func keywordPromptGetsTheSummaryAndRecentEarlierQuestionsWithinALimit() {
        let long = String(repeating: "q", count: 290)
        let prompt = BibleQuestionPrompt.keywords(
            for: "What did that brother make?",
            previous: .init(question: "Where did the family flee?", answer: ""),
            earlierQuestions: [long, "Who was Moses' brother?", "Where was Jesus born?"],
            summary: "They talked about Aaron, Moses' brother."
        )
        // The oldest question no longer fits the 300-character limit.
        #expect(prompt.user == """
        Earlier conversation: They talked about Aaron, Moses' brother.
        Earlier questions: Who was Moses' brother? | Where was Jesus born?
        Previous question: Where did the family flee?
        Question: What did that brother make?
        """)
        #expect(prompt.system.contains("earlier conversation"))
    }

    @Test
    func answerPromptWithoutPassagesSaysNothingWasFound() {
        let prompt = BibleQuestionPrompt.answer(question: "Q?", passages: [])
        #expect(prompt.user.contains("No passages were found"))
    }
}

struct SearchProfileTests {
    private func spanishPassage() throws -> BibleQuestionPrompt.Passage {
        let verse = try BibleVerse(
            reference: BibleReference(bookID: "MAT", chapter: 2, verse: 1),
            text: "Y como fué nacido Jesús en Bethlehem de Judea"
        )
        return BibleQuestionPrompt.Passage(
            bookName: "Mateo",
            passage: BiblePassage(bookID: "MAT", chapter: 2, verses: [verse])
        )
    }

    @Test
    func theKJVProfileKeepsTheEnglishPromptText() {
        let prompt = BibleQuestionPrompt.keywords(for: "¿Dónde nació Jesús?", profile: .kjv)
        #expect(prompt == BibleQuestionPrompt.keywords(for: "¿Dónde nació Jesús?"))
        #expect(prompt.system.contains("search keywords for the English King James Version"))
    }

    @Test
    func versionProfilesFollowTheTextsLanguage() throws {
        let rv = try BibleVersion(id: "rv1909", name: "Reina-Valera 1909", abbreviation: "RV1909", languageCode: "es", copyright: "")
        let profile = BibleQuestionPrompt.SearchProfile(version: rv)
        #expect(profile.languageName == "Spanish")

        let keywords = BibleQuestionPrompt.keywords(for: "Where was Jesus born?", profile: profile)
        #expect(keywords.system.contains("search keywords for the Spanish Reina-Valera 1909"))
        #expect(keywords.system.contains("3 to 8 Spanish words"))
        #expect(!keywords.system.contains("King James"))

        let answer = BibleQuestionPrompt.answer(question: "Where was Jesus born?", passages: [try spanishPassage()], profile: profile)
        #expect(answer.user.contains("Passages (Reina-Valera 1909):"))
        #expect(answer.user.contains("Mateo 2:1 Y como fué nacido"))
        #expect(answer.system.contains("[Mateo 2:1]"))
        #expect(answer.system.contains("using the book names shown in the passages"))
        #expect(!answer.system.contains("English book names"))
    }

    @Test
    func portugueseAndOtherLanguagesGetProfiles() throws {
        let almeida = try BibleVersion(id: "almeida", name: "Almeida", abbreviation: "ARC", languageCode: "pt-BR", copyright: "")
        #expect(BibleQuestionPrompt.SearchProfile(version: almeida).citationExample == "[Mateus 2:1]")

        let german = try BibleVersion(id: "lut", name: "Luther 1912", abbreviation: "LUT", languageCode: "de", copyright: "")
        let profile = BibleQuestionPrompt.SearchProfile(version: german)
        #expect(profile.languageName == "German")
        let keywords = BibleQuestionPrompt.keywords(for: "Wo wurde Jesus geboren?", profile: profile)
        #expect(keywords.system.contains("German Luther 1912"))
    }
}
