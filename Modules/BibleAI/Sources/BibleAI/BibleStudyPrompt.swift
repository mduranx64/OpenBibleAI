//
//  BibleStudyPrompt.swift
//  BibleAI
//

/// The system and user prompts every study engine receives for a request:
/// the selected verse, optional chapter context (marked as background) and
/// the question. Engines differ only in how they send these two strings.
public struct BibleStudyPrompt: Equatable, Sendable {
    public let system: String
    public let user: String
    /// True when the prompt only transforms the user's own text (e.g. into
    /// search keywords). Apple's model then uses its guardrail mode for
    /// content transformations, which avoids false refusals such as
    /// "heal a blind person" being treated as unsafe.
    public let isContentTransformation: Bool

    public init(system: String, user: String, isContentTransformation: Bool = false) {
        self.system = system
        self.user = user
        self.isContentTransformation = isContentTransformation
    }

    init(_ request: BibleStudyRequest) {
        let reference = request.verse.reference
        let bookName = request.bookName ?? reference.bookID

        let systemPrompt = """
        You are a careful Bible study assistant.
        Base your answer on the supplied biblical passage.
        Use any chapter context only as background for understanding the \
        selected verse; the question is about the selected verse.
        Clearly distinguish the text from interpretation.
        Do not invent Scripture citations.
        """

        var userPrompt = """
        Passage: \(bookName) \
        \(reference.chapter):\(reference.verse)

        Selected verse:
        \(request.verse.text)
        """

        if !request.context.isEmpty {
            let lines = request.context.map { verse in
                let marker = verse.reference == reference ? "> " : ""
                return "\(marker)[\(verse.reference.verse)] \(verse.text)"
            }.joined(separator: "\n")

            userPrompt += """


            Chapter context (background only; the selected verse is \
            marked with >):
            \(lines)
            """
        }

        userPrompt += """


        Question:
        \(request.question)
        """

        self.system = systemPrompt
        self.user = userPrompt
        self.isContentTransformation = false
    }
}
