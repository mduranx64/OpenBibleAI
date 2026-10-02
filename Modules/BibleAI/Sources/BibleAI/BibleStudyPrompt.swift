//
//  BibleStudyPrompt.swift
//  BibleAI
//

/// The system and user prompts every study engine receives for a request:
/// the selected verse, optional chapter context (marked as background) and
/// the question. Engines differ only in how they send these two strings.
struct BibleStudyPrompt: Equatable, Sendable {
    let system: String
    let user: String

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
    }
}
