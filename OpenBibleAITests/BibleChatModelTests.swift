import BibleAI
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

@MainActor
struct BibleChatModelTests {
    private func repository() throws -> InMemoryBibleRepository {
        func verse(_ book: String, _ chapter: Int, _ number: Int, _ text: String) throws -> BibleVerse {
            try BibleVerse(reference: BibleReference(bookID: book, chapter: chapter, verse: number), text: text)
        }
        return InMemoryBibleRepository(
            verses: try [
                verse("MAT", 2, 1, "Now when Jesus was born in Bethlehem of Judaea in the days of Herod the king"),
                verse("MAT", 2, 2, "Saying, Where is he that is born King of the Jews?"),
                verse("JOH", 9, 1, "And as Jesus passed by, he saw a man which was blind from his birth."),
                verse("JOH", 9, 7, "He went his way therefore, and washed, and came seeing.")
            ],
            books: [
                try BibleBook(bookID: "MAT", name: "Matthew", canonicalOrder: 40),
                try BibleBook(bookID: "JOH", name: "John", canonicalOrder: 43)
            ]
        )
    }

    private func model(
        streamer: FakeStreamer,
        repository: InMemoryBibleRepository,
        store: InMemoryChatStore = InMemoryChatStore(),
        budget: Int = 6_000,
        semanticSearch: (@Sendable (String) async throws -> [RankedVerse])? = nil
    ) -> BibleChatModel {
        BibleChatModel(
            passages: repository,
            verses: repository,
            books: { try await repository.books() },
            engine: .init(makeStreamer: { streamer }, passageBudget: { budget }, semanticSearch: { semanticSearch }),
            store: store
        )
    }

    private func lastAnswer(_ model: BibleChatModel) throws -> ChatMessage {
        let message = try #require(model.conversation.messages.last)
        #expect(message.role == .assistant)
        return message
    }

    @Test
    func answersFromRetrievedPassagesAndVerifiesCitations() async throws {
        let streamer = FakeStreamer(
            keywords: "born, Bethlehem",
            answer: ["Jesus was born in Bethlehem ", "[Matthew 2:1]. See also [Matthew 2:99], [John 9:7] and [Hezekiah 1:1]."]
        )
        let model = model(streamer: streamer, repository: try repository())

        await model.send("  Where was Jesus born? ").value

        #expect(model.phase == .idle)
        #expect(model.conversation.title == "Where was Jesus born?")
        #expect(model.conversation.messages.map(\.role) == [.user, .assistant])
        let answer = try lastAnswer(model)
        #expect(answer.status == .completed)
        #expect(answer.text.hasPrefix("Jesus was born in Bethlehem [Matthew 2:1]"))
        #expect(answer.sources.first?.title == "Matthew 2:1–2")
        #expect(streamer.answerPrompts.last?.user.contains("Matthew 2:1 Now when Jesus was born in Bethlehem") == true)

        let items = (model.citations[answer.id] ?? []).flatMap(\.items)
        #expect(items.count == 4)
        #expect(items[0].reference == (try BibleReference(bookID: "MAT", chapter: 2, verse: 1)))
        #expect(items[0].status == .grounded)
        #expect(items[1].status == .notFound, "Matthew 2:99 is not in the Bible")
        #expect(items[2].status == .outsideSources, "John 9:7 exists but was not retrieved for this question")
        #expect(items[3].status == .notFound && items[3].reference == nil, "Unknown book")
    }

    @Test
    func failedKeywordStepFallsBackToTheQuestionWords() async throws {
        let streamer = FakeStreamer(keywords: nil, answer: ["A man blind from his birth was healed [John 9:1]."])
        let model = model(streamer: streamer, repository: try repository())

        await model.send("Where did Jesus heal a blind man?").value

        let answer = try lastAnswer(model)
        #expect(answer.status == .completed)
        #expect(answer.sources.contains { $0.title.hasPrefix("John 9:") })
        #expect(model.citations[answer.id]?.flatMap(\.items).first?.status == .grounded)
    }

    @Test
    func semanticSearchAddsPassagesKeywordsMiss() async throws {
        let streamer = FakeStreamer(keywords: "zzzqxj", answer: ["He washed and saw [John 9:7]."])
        let healing = try BibleReference(bookID: "JOH", chapter: 9, verse: 7)
        let model = model(
            streamer: streamer,
            repository: try repository(),
            semanticSearch: { _ in [RankedVerse(reference: healing, score: 0.9)] }
        )

        await model.send("¿Dónde sanó Jesús a un ciego?").value

        let answer = try lastAnswer(model)
        #expect(answer.usedSemanticSearch)
        #expect(answer.sources.contains { $0.bookID == "JOH" && $0.chapter == 9 })
        #expect(model.citations[answer.id]?.flatMap(\.items).first?.status == .grounded)
    }

    @Test
    func failingSemanticSearchFallsBackToKeywords() async throws {
        let streamer = FakeStreamer(keywords: "born, Bethlehem", answer: ["Bethlehem [Matthew 2:1]."])
        let model = model(
            streamer: streamer,
            repository: try repository(),
            semanticSearch: { _ in throw AIEngineError.modelUnavailable }
        )

        await model.send("Where was Jesus born?").value

        let answer = try lastAnswer(model)
        #expect(answer.status == .completed)
        #expect(!answer.usedSemanticSearch)
        #expect(answer.sources.first?.title == "Matthew 2:1–2")
    }

    @Test
    func unavailableEngineFailsWithItsMessageAndIsSaved() async throws {
        let repository = try repository()
        let store = InMemoryChatStore()
        let model = BibleChatModel(
            passages: repository,
            verses: repository,
            books: { try await repository.books() },
            engine: .init(makeStreamer: { throw AIEngineError.modelUnavailable }, passageBudget: { 6_000 }),
            store: store
        )

        await model.send("Where was Jesus born?").value

        #expect(try lastAnswer(model).status == .failed(AIEngineError.modelUnavailable.errorDescription ?? ""))
        #expect(model.phase == .idle)
        #expect(model.summaries.map(\.id) == [model.conversation.id])
    }

    @Test
    func followUpsSendEarlierTurnsAndThePreviousQuestion() async throws {
        let streamer = FakeStreamer(keywords: "born, Bethlehem", answer: ["In Bethlehem [Matthew 2:1]."])
        let model = model(streamer: streamer, repository: try repository())

        await model.send("Where was Jesus born?").value
        await model.send("Who was king then?").value

        #expect(model.conversation.messages.count == 4)
        #expect(model.conversation.title == "Where was Jesus born?", "The title comes from the first question")
        let keywordPrompt = try #require(streamer.keywordPrompts.last)
        #expect(keywordPrompt.user.hasPrefix("Previous question: Where was Jesus born?\nPrevious answer: In Bethlehem [Matthew 2:1]."))
        let answerPrompt = try #require(streamer.answerPrompts.last)
        #expect(answerPrompt.user.contains("User: Where was Jesus born?\nAssistant: In Bethlehem [Matthew 2:1]."))
        #expect(answerPrompt.user.contains("Question:\nWho was king then?"))
        #expect(streamer.answerPrompts.first?.user.contains("Earlier conversation") == false)
    }

    @Test
    func followUpsKeepThePassagesThePreviousAnswerCited() async throws {
        // Keywords for the follow-up find nothing; the cited verse carries over.
        let streamer = FakeStreamer(keywords: "zzzqxj", answer: ["He came seeing [John 9:7]."])
        let healing = try BibleReference(bookID: "JOH", chapter: 9, verse: 7)
        let model = model(
            streamer: streamer,
            repository: try repository(),
            // Only the first question finds the healing; the follow-up's
            // own search finds nothing.
            semanticSearch: { question in
                question.contains("Who was it?") ? [] : [RankedVerse(reference: healing, score: 0.9)]
            }
        )

        await model.send("Where did Jesus heal a blind man?").value
        await model.send("Who was it?").value

        let answer = try lastAnswer(model)
        #expect(answer.sources.contains { $0.bookID == "JOH" && $0.chapter == 9 })
        #expect(model.citations[answer.id]?.flatMap(\.items).first?.status == .grounded)
    }

    @Test
    func earlierTurnsBeyondTheEngineBudgetAreLeftOut() async throws {
        let long = String(repeating: "Bethlehem ", count: 20)
        let streamer = FakeStreamer(keywords: "born", answer: [long])
        // Budget 300 → up to 100 characters of history; the first turn is ~220.
        let model = model(streamer: streamer, repository: try repository(), budget: 300)

        await model.send("Where was Jesus born?").value
        await model.send("Why there?").value

        #expect(streamer.answerPrompts.last?.user.contains("Earlier conversation") == false)
    }

    @Test
    func attachedVerseIsSentShownOnTheQuestionAndThenCleared() async throws {
        let repository = try repository()
        let streamer = FakeStreamer(keywords: "zzzqxj", answer: ["He healed him [John 9:7]."])
        let model = model(streamer: streamer, repository: repository)
        let chapter = try await repository.verses(in: "JOH", chapter: 9)
        let verse = try #require(chapter.first)

        model.attach(verse: verse, bookName: "John", chapterVerses: chapter)
        #expect(model.attachedVerse?.title == "John 9:1")
        await model.send("What happened next?").value

        #expect(model.attachedVerse == nil, "An attached verse applies to one question")
        #expect(model.conversation.messages.first?.attachedVerse?.title == "John 9:1")
        #expect(streamer.keywordPrompts.last?.user.contains("About the verse: John 9:1") == true)
        #expect(streamer.answerPrompts.last?.user.contains("The user is asking about John 9:1:\nJohn 9:1 And as Jesus passed by") == true)
        let answer = try lastAnswer(model)
        #expect(answer.sources.first?.title == "John 9:1–7", "The verse's chapter context counts as a source")
        #expect(model.citations[answer.id]?.flatMap(\.items).first?.status == .grounded)
    }

    @Test
    func detachRemovesTheVerseBeforeSending() async throws {
        let repository = try repository()
        let streamer = FakeStreamer(keywords: "born", answer: ["Bethlehem [Matthew 2:1]."])
        let model = model(streamer: streamer, repository: repository)
        let verse = try #require(try await repository.verses(in: "JOH", chapter: 9).first)

        model.attach(verse: verse, bookName: "John", chapterVerses: [verse])
        model.detach()
        await model.send("Where was Jesus born?").value

        #expect(model.conversation.messages.first?.attachedVerse == nil)
        #expect(streamer.answerPrompts.last?.user.contains("The user is asking about") == false)
    }

    @Test
    func stopKeepsTheExchangeMarksItStoppedAndSaves() async throws {
        let gate = AnswerGate()
        let store = InMemoryChatStore()
        let streamer = FakeStreamer(keywords: "born", answer: ["Late."], gate: gate)
        let model = model(streamer: streamer, repository: try repository(), store: store)

        let task = model.send("Where was Jesus born?")
        await gate.waitUntilStarted()
        model.stop()
        await gate.release()
        await task.value

        #expect(model.phase == .idle)
        #expect(try lastAnswer(model).status == .stopped)
        #expect(try lastAnswer(model).text.isEmpty, "Chunks after Stop are ignored")
        try await waitUntil { await store.saveCount > 0 }
        #expect(try await store.load(model.conversation.id).messages.last?.status == .stopped)
    }

    @Test
    func newerQuestionStopsTheOlderAnswer() async throws {
        let gate = AnswerGate()
        let streamer = FakeStreamer(keywords: "born", answer: ["Newer answer [Matthew 2:1]."], gate: gate)
        let model = model(streamer: streamer, repository: try repository())

        let first = model.send("First?")
        await gate.waitUntilStarted()
        streamer.gate = nil
        await model.send("Second?").value
        await gate.release()
        await first.value

        let messages = model.conversation.messages
        #expect(messages.map(\.text) == ["First?", "", "Second?", "Newer answer [Matthew 2:1]."])
        #expect(messages[1].status == .stopped)
        #expect(messages[3].status == .completed)
    }

    @Test
    func savedChatReopensWithItsCitationsCheckedAgain() async throws {
        let store = InMemoryChatStore()
        let streamer = FakeStreamer(keywords: "born, Bethlehem", answer: ["In Bethlehem [Matthew 2:1]."])
        let model = model(streamer: streamer, repository: try repository(), store: store)

        await model.send("Where was Jesus born?").value
        let saved = model.conversation
        model.newChat()

        #expect(model.conversation.messages.isEmpty)
        #expect(model.summaries.map(\.title) == ["Where was Jesus born?"])

        await model.open(saved.id)

        #expect(model.conversation.messages.map(\.text) == saved.messages.map(\.text))
        let answer = try lastAnswer(model)
        #expect(model.citations[answer.id]?.flatMap(\.items).map(\.status) == [.grounded])
    }

    @Test
    func deletingTheOpenChatStartsANewOne() async throws {
        let store = InMemoryChatStore()
        let streamer = FakeStreamer(keywords: "born", answer: ["Bethlehem [Matthew 2:1]."])
        let model = model(streamer: streamer, repository: try repository(), store: store)

        await model.send("Where was Jesus born?").value
        let id = model.conversation.id
        await model.delete(id)

        #expect(model.conversation.id != id)
        #expect(model.conversation.messages.isEmpty)
        #expect(model.summaries.isEmpty)
        #expect(try await store.summaries().isEmpty)
    }

    @Test
    func blankQuestionsAreIgnored() async throws {
        let streamer = FakeStreamer(keywords: "born", answer: ["x"])
        let model = model(streamer: streamer, repository: try repository())

        await model.send("   \n").value

        #expect(model.conversation.messages.isEmpty)
        #expect(model.phase == .idle)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 where !(await condition()) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await condition())
    }
}

/// Answers the keyword prompt with `keywords` (or throws when nil) and
/// streams `answer` for the answer prompt, optionally waiting on a gate.
private final class FakeStreamer: AIPromptStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private let keywords: String?
    private let answer: [String]
    private var _gate: AnswerGate?
    private var _keywordPrompts: [BibleStudyPrompt] = []
    private var _answerPrompts: [BibleStudyPrompt] = []

    init(keywords: String?, answer: [String], gate: AnswerGate? = nil) {
        self.keywords = keywords
        self.answer = answer
        self._gate = gate
    }

    var gate: AnswerGate? {
        get { lock.withLock { _gate } }
        set { lock.withLock { _gate = newValue } }
    }

    var keywordPrompts: [BibleStudyPrompt] { lock.withLock { _keywordPrompts } }
    var answerPrompts: [BibleStudyPrompt] { lock.withLock { _answerPrompts } }

    func streamResponse(to prompt: BibleStudyPrompt) -> AsyncThrowingStream<String, Error> {
        let isKeywordStep = prompt.system.contains("search keywords")
        lock.withLock {
            if isKeywordStep { _keywordPrompts.append(prompt) } else { _answerPrompts.append(prompt) }
        }
        let gate = isKeywordStep ? nil : self.gate
        let keywords = self.keywords
        let answer = self.answer

        return AsyncThrowingStream { continuation in
            Task {
                if isKeywordStep {
                    if let keywords {
                        continuation.yield(keywords)
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: AIEngineError.timedOut)
                    }
                    return
                }
                await gate?.enter()
                for delta in answer { continuation.yield(delta) }
                continuation.finish()
            }
        }
    }
}

private actor AnswerGate {
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var held: CheckedContinuation<Void, Never>?

    func enter() async {
        entered = true
        waiters.forEach { $0.resume() }
        waiters = []
        await withCheckedContinuation { held = $0 }
    }

    func waitUntilStarted() async {
        if entered { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

@MainActor
struct CitationTextTests {
    @Test
    func citationLinksRoundTripAndRejectOtherURLs() throws {
        let reference = try BibleReference(bookID: "1JO", chapter: 1, verse: 5)
        let url = try #require(CitationLink.url(for: reference))

        #expect(url.absoluteString == "openbible://verse/1JO/1/5")
        #expect(CitationLink.reference(from: url) == reference)
        #expect(CitationLink.reference(from: URL(string: "https://example.com/verse/JOH/3/16")!) == nil)
    }

    @Test
    func onlyVerifiedCitationsBecomeLinks() throws {
        let answer = "Born in Bethlehem [Matthew 2:1] or [Hezekiah 1:1]."
        let first = answer.range(of: "[Matthew 2:1]")!
        let second = answer.range(of: "[Hezekiah 1:1]")!
        let reference = try BibleReference(bookID: "MAT", chapter: 2, verse: 1)
        let citations = [
            BibleChatModel.ResolvedCitation(range: first, items: [.init(label: "Matthew 2:1", reference: reference, status: .grounded)]),
            BibleChatModel.ResolvedCitation(range: second, items: [.init(label: "Hezekiah 1:1", reference: nil, status: .notFound)])
        ]

        let text = CitationText.attributed(answer, citations: citations)
        let links = text.runs.compactMap(\.link)

        #expect(links == [CitationLink.url(for: reference)!])
        #expect(CitationText.hasUnverified(citations))
    }
}
