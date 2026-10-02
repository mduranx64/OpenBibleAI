//
//  BibleQuestionPrompt.swift
//  BibleAI
//

import BibleDomain
import Foundation
import NaturalLanguage

/// Prompts for the Bible chat: first search keywords, then an answer
/// grounded only in retrieved passages (and an attached verse), with
/// bracketed citations. Earlier turns are context, not sources.
public enum BibleQuestionPrompt {
    /// Characters of earlier conversation sent with a question by default.
    public static let defaultHistoryCharacterLimit = 2_000

    /// An earlier exchange in the conversation.
    public struct Turn: Equatable, Sendable {
        public let question: String
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// A verse the user attached to the question, with nearby verses from
    /// its chapter (see `BibleStudyContext`).
    public struct FocusVerse: Equatable, Sendable {
        public let bookName: String
        public let verse: BibleVerse
        public let context: [BibleVerse]

        public init(bookName: String, verse: BibleVerse, context: [BibleVerse]) {
            self.bookName = bookName
            self.verse = verse
            self.context = context
        }

        var reference: String {
            "\(bookName) \(verse.reference.chapter):\(verse.reference.verse)"
        }
    }

    public struct Passage: Equatable, Sendable {
        public let bookName: String
        public let passage: BiblePassage

        public init(bookName: String, passage: BiblePassage) {
            self.bookName = bookName
            self.passage = passage
        }
    }

    /// Characters of the previous answer shown to the keyword step.
    public static let previousAnswerCharacterLimit = 400

    /// Asks for English King James search words for a question in any language.
    /// The previous turn and `focus` let follow-ups like "and where did he
    /// die?" or "what does this mean?" resolve to the right subject.
    public static func keywords(
        for question: String,
        previous: Turn? = nil,
        focus: FocusVerse? = nil
    ) -> BibleStudyPrompt {
        var user = question
        var context: [String] = []
        if let previous {
            context.append("Previous question: \(previous.question)")
            if !previous.answer.isEmpty {
                context.append("Previous answer: \(previous.answer.prefix(previousAnswerCharacterLimit))")
            }
        }
        if let focus { context.append("About the verse: \(focus.reference) \(focus.verse.text)") }
        if !context.isEmpty {
            user = context.joined(separator: "\n") + "\nQuestion: " + question
        }

        return BibleStudyPrompt(
            system: """
            You turn questions about the Bible into search keywords for the English King James Version.
            Reply with 3 to 8 English words separated by commas, using King James vocabulary \
            (for example "healed", "sight", "begat"). Include the key people and places, \
            and always the English words for the question's main subject \
            (for example "blind" for "ciego"). \
            Translate questions asked in other languages. \
            Use the previous question, previous answer or verse, when given, to understand what the question refers to. \
            No explanations.
            """,
            user: user,
            isContentTransformation: true
        )
    }

    /// Asks for a short answer using only `passages` (and `focus`), citing
    /// every claim. The most recent `history` that fits
    /// `historyCharacterLimit` is included so follow-ups make sense.
    public static func answer(
        question: String,
        passages: [Passage],
        history: [Turn] = [],
        focus: FocusVerse? = nil,
        historyCharacterLimit: Int = defaultHistoryCharacterLimit
    ) -> BibleStudyPrompt {
        let system = """
        You answer questions about the Bible using only the passages provided.
        Earlier conversation is only context for follow-up questions; do not cite it.
        Cite every statement with its verse in square brackets, exactly like [Matthew 2:1] \
        or [Luke 2:4-7], using the English book names shown in the passages.
        Do not cite verses that are not in the passages.
        If the passages do not answer the question, say so briefly.
        Do not quote or translate the verses; summarize them in your own words and cite them.
        Write the whole answer in the same language as the question, in two to five sentences.
        Clearly separate what the text says from interpretation.
        """

        var sections: [String] = []

        let turns = trimmedHistory(history, characterLimit: historyCharacterLimit)
        if !turns.isEmpty {
            sections.append("Earlier conversation:\n" + turns.map {
                "User: \($0.question)\nAssistant: \($0.answer)"
            }.joined(separator: "\n"))
        }

        if let focus {
            let lines = (focus.context.isEmpty ? [focus.verse] : focus.context).map { verse in
                "\(focus.bookName) \(verse.reference.chapter):\(verse.reference.verse) \(verse.text)"
            }
            sections.append(
                "The user is asking about \(focus.reference):\n" + lines.joined(separator: "\n")
            )
        }

        let body: String
        if passages.isEmpty {
            body = "No passages were found for this question."
        } else {
            body = passages.map { item in
                item.passage.verses.map { verse in
                    "\(item.bookName) \(verse.reference.chapter):\(verse.reference.verse) \(verse.text)"
                }.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }

        // Small models drift into English or into translating verses, so the
        // language and the no-quoting rule are repeated next to the question.
        let language = answerLanguageName(for: question).map { "in \($0)" } ?? "in the language of the question"

        return BibleStudyPrompt(
            system: system,
            user: """
            \(sections.map { $0 + "\n\n" }.joined())Passages (King James Version):
            \(body)

            Question:
            \(question)

            Write your answer \(language). Cite verses in brackets with the English book names shown, like [Matthew 2:1]. Summarize the verses; do not quote or translate them.
            """
        )
    }
}

extension BibleQuestionPrompt {
    /// The most recent turns whose text fits `characterLimit`, oldest first.
    /// Older turns are dropped whole; a single turn longer than the limit is
    /// dropped too, so the prompt stays bounded.
    public static func trimmedHistory(_ history: [Turn], characterLimit: Int) -> [Turn] {
        var kept: [Turn] = []
        var used = 0
        for turn in history.reversed() {
            let size = turn.question.count + turn.answer.count
            guard used + size <= characterLimit else { break }
            used += size
            kept.append(turn)
        }
        return kept.reversed()
    }

    /// English name of the question's dominant language ("Spanish"), or nil
    /// when it can't be recognised with reasonable confidence.
    static func answerLanguageName(for question: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(question)
        guard let language = recognizer.dominantLanguage,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[language],
              confidence >= 0.5
        else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue)
    }
}

/// Parses the model's keyword reply: commas, semicolons or lines; bullets,
/// numbering, quotes and labels removed; case-insensitive duplicates dropped.
public enum SearchKeywordParser {
    public static let maximumCount = 12

    public static func keywords(from response: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        let lines = response.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
        for line in lines {
            var text = String(line)
            if let colon = text.firstIndex(of: ":") { text = String(text[text.index(after: colon)...]) }
            for word in text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
                let cleaned = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
                guard cleaned.count > 1, !seen.contains(cleaned.lowercased()) else { continue }
                seen.insert(cleaned.lowercased())
                result.append(cleaned)
                if result.count == maximumCount { return result }
            }
        }
        return result
    }
}
