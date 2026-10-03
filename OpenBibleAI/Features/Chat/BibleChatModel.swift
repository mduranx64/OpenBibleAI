import BibleAI
import BibleDomain
import Foundation
import Observation

/// The Bible chat: answers questions from passages retrieved from the
/// reading version (plus an attached verse), remembers recent turns for
/// follow-ups, checks every answer's citations, and saves conversations on
/// device. App-level, so a chat survives verse and version changes (tapping
/// a citation opens a verse).
@MainActor
@Observable
final class BibleChatModel {
    /// The generation engine, read for every question so it follows the
    /// current choice (Apple model or downloaded model).
    struct Engine {
        let makeStreamer: @MainActor @Sendable () throws -> any AIPromptStreaming
        /// Characters of Bible text (passages, attached verse) and earlier
        /// conversation the engine can take with one question.
        let passageBudget: @MainActor @Sendable () -> Int
        /// Meaning-based ranking for a question, when the optional search
        /// model is installed; nil otherwise.
        let semanticSearch: @MainActor @Sendable () -> (@Sendable (String) async throws -> [RankedVerse])?

        init(
            makeStreamer: @escaping @MainActor @Sendable () throws -> any AIPromptStreaming,
            passageBudget: @escaping @MainActor @Sendable () -> Int,
            semanticSearch: @escaping @MainActor @Sendable () -> (@Sendable (String) async throws -> [RankedVerse])? = { nil }
        ) {
            self.makeStreamer = makeStreamer
            self.passageBudget = passageBudget
            self.semanticSearch = semanticSearch
        }

        static var unavailable: Engine {
            Engine(
                makeStreamer: { throw AIEngineError.modelUnavailable },
                passageBudget: { BibleStudyContext.defaultCharacterLimit }
            )
        }
    }

    /// One installed version's text, searched and cited by the chat.
    struct Bible: Sendable {
        let version: BibleVersion
        let passages: any BiblePassageSearchRepository
        let verses: any BibleRepository
        let books: @Sendable () async throws -> [BibleBook]
    }

    /// The version an older chat without a recorded version was answered from.
    static let defaultVersionID = "kjv"

    /// Progress of the answer being generated, if any.
    enum Phase: Equatable {
        case idle
        case searching
        case answering
    }

    /// A verse selected in the reader, shown as a removable chip and sent
    /// with the next question.
    struct AttachedVerse: Equatable {
        let verse: BibleVerse
        let bookName: String
        let chapterVerses: [BibleVerse]

        var title: String {
            "\(bookName) \(verse.reference.chapter):\(verse.reference.verse)"
        }
    }

    /// A citation found in an answer, after checking it against the Bible.
    struct ResolvedCitation: Equatable {
        enum Status: Equatable {
            /// Every cited verse is in the passages the answer was given.
            case grounded
            /// The verses exist, but were not among the passages the answer
            /// was given, so the answer's claim about them was not checked.
            case outsideSources
            /// Unknown book, unreadable citation, or a verse that doesn't exist.
            case notFound
        }

        struct Item: Equatable {
            let label: String
            /// Nil when the citation could not be read (e.g. unknown book).
            let reference: BibleReference?
            let status: Status

            var isVerified: Bool { status == .grounded }
        }

        /// Range of the citation within the message text.
        let range: Range<String.Index>
        let items: [Item]
    }

    private(set) var conversation = ChatConversation()
    private(set) var phase: Phase = .idle
    private(set) var attachedVerse: AttachedVerse?
    /// Saved chats, newest first.
    private(set) var summaries: [ChatSummary] = []
    /// Checked citations per assistant message.
    private(set) var citations: [UUID: [ResolvedCitation]] = [:]

    /// The reading version's Bible (nil) or a given version's, for
    /// re-checking the citations of a saved answer.
    @ObservationIgnored private let bible: @MainActor (String?) async throws -> Bible
    @ObservationIgnored private let engine: Engine
    @ObservationIgnored private let store: any ChatStore
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The background summary of turns that dropped out of the history
    /// budget; exposed so tests can wait for it.
    @ObservationIgnored private(set) var summaryTask: Task<Void, Never>?
    @ObservationIgnored private var summaryGeneration = 0

    static let rankedVerseLimit = 20
    static let passageWindow = 2
    static let passageLimit = 6
    static let titleLength = 60
    static let carriedReferenceLimit = 4

    init(
        bible: @escaping @MainActor (String?) async throws -> Bible,
        engine: Engine,
        store: any ChatStore
    ) {
        self.bible = bible
        self.engine = engine
        self.store = store
    }

    /// One fixed Bible (the KJV) for every question and saved chat.
    convenience init(
        passages: any BiblePassageSearchRepository,
        verses: any BibleRepository,
        books: @escaping @Sendable () async throws -> [BibleBook],
        engine: Engine,
        store: any ChatStore
    ) {
        let version: BibleVersion
        do {
            version = try BibleVersion(
                id: Self.defaultVersionID, name: "King James Version", abbreviation: "KJV",
                languageCode: "en", copyright: "Public domain"
            )
        } catch {
            preconditionFailure("Invalid default version: \(error)")
        }
        let fixed = Bible(version: version, passages: passages, verses: verses, books: books)
        self.init(bible: { _ in fixed }, engine: engine, store: store)
    }

    var isAnswering: Bool { phase != .idle }

    // MARK: - Attached verse

    func attach(verse: BibleVerse, bookName: String, chapterVerses: [BibleVerse]) {
        attachedVerse = AttachedVerse(verse: verse, bookName: bookName, chapterVerses: chapterVerses)
    }

    func detach() {
        attachedVerse = nil
    }

    // MARK: - Asking

    /// Sends `text` with the attached verse (which is then cleared) and
    /// starts answering it. An answer in progress is stopped first.
    @discardableResult
    func send(_ text: String) -> Task<Void, Never> {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return Task {} }
        if isAnswering { stop() }

        generation += 1
        let requestGeneration = generation

        // Context from earlier turns, before this question is added: the
        // summary of older turns, then the turns after it.
        let history = Self.turns(in: conversation.messages, from: conversation.summarizedMessageCount ?? 0).map(\.turn)
        let summary = conversation.historySummary
        // All earlier questions (short) except the latest, which goes with its answer.
        let earlierQuestions = Array(conversation.messages.filter { $0.role == .user }.map(\.text).dropLast())
        let carried = carriedReferences()
        let focus = attachedVerse
        attachedVerse = nil

        if conversation.title.isEmpty {
            conversation.title = String(question.prefix(Self.titleLength))
        }
        conversation.messages.append(ChatMessage(
            role: .user,
            text: question,
            attachedVerse: focus.map {
                ChatVerseRange(
                    bookID: $0.verse.reference.bookID,
                    chapter: $0.verse.reference.chapter,
                    firstVerse: $0.verse.reference.verse,
                    lastVerse: $0.verse.reference.verse,
                    bookName: $0.bookName
                )
            }
        ))
        let answer = ChatMessage(role: .assistant, text: "")
        conversation.messages.append(answer)
        phase = .searching

        let request = Request(
            question: question,
            history: history,
            summary: summary,
            earlierQuestions: earlierQuestions,
            carried: carried,
            focus: focus,
            messageID: answer.id,
            generation: requestGeneration
        )
        let newTask = Task { await run(request) }
        task = newTask
        return newTask
    }

    /// Stops the answer in progress, keeping what was generated so far.
    func stop() {
        guard isAnswering else { return }
        generation += 1
        task?.cancel()
        task = nil
        phase = .idle
        if let index = conversation.messages.lastIndex(where: { $0.role == .assistant }) {
            conversation.messages[index].status = .stopped
        }
        // Saved from a snapshot: New Chat may replace `conversation` first.
        let snapshot = stampedConversation()
        Task { await persist(snapshot) }
    }

    // MARK: - Conversations

    /// Starts an empty chat; the current one is already saved.
    func newChat() {
        stop()
        generation += 1
        cancelSummary()
        conversation = ChatConversation()
        citations = [:]
    }

    func loadSummaries() async {
        summaries = (try? await store.summaries()) ?? []
    }

    func open(_ id: UUID) async {
        stop()
        generation += 1
        cancelSummary()
        let requestGeneration = generation
        guard let loaded = try? await store.load(id), requestGeneration == generation else { return }

        conversation = loaded
        citations = [:]
        // Each answer is checked against the version it was answered from;
        // one whose version isn't installed shows its citations unlinked.
        var loadedBibles: [String: (Bible, [BibleBook])] = [:]
        for message in loaded.messages where message.role == .assistant {
            let id = message.versionID ?? Self.defaultVersionID
            if loadedBibles[id] == nil, let bible = try? await self.bible(id), let books = try? await bible.books() {
                loadedBibles[id] = (bible, books)
            }
            guard requestGeneration == generation else { return }
            guard let (bible, books) = loadedBibles[id] else { continue }
            let grounding = Set(message.sources.flatMap(\.references))
            let resolved = await resolveCitations(
                in: message.text, bible: bible, books: books, names: Self.names(for: books), grounding: grounding
            )
            guard requestGeneration == generation else { return }
            citations[message.id] = resolved
        }
    }

    func delete(_ id: UUID) async {
        if id == conversation.id { newChat() }
        try? await store.delete(id)
        await loadSummaries()
    }

    // MARK: - Pipeline

    private struct Request {
        let question: String
        let history: [BibleQuestionPrompt.Turn]
        let summary: String?
        let earlierQuestions: [String]
        /// Verses the previous answer cited (checked), kept in view for follow-ups.
        let carried: [BibleReference]
        let focus: AttachedVerse?
        let messageID: UUID
        let generation: Int
    }

    private func run(_ request: Request) async {
        func isCurrent() -> Bool { request.generation == generation && !Task.isCancelled }

        do {
            let streamer = try engine.makeStreamer()
            let bible = try await self.bible(nil)
            let books = try await bible.books()
            let names = Self.names(for: books)
            let profile = BibleQuestionPrompt.SearchProfile(version: bible.version)
            updateAnswer(request.messageID) { $0.versionID = bible.version.id }

            // The budget is shared: up to a third each for earlier
            // conversation and the attached verse's chapter, the rest (at
            // least a third) for retrieved passages.
            let budget = engine.passageBudget()
            let historyLimit = Self.historyLimit(budget: budget, summary: request.summary)
            let history = BibleQuestionPrompt.trimmedHistory(request.history, characterLimit: historyLimit)
            let historyCharacters = (request.summary?.count ?? 0)
                + history.reduce(0) { $0 + $1.question.count + $1.answer.count }
            let focus = request.focus.map { attached in
                BibleQuestionPrompt.FocusVerse(
                    bookName: attached.bookName,
                    verse: attached.verse,
                    context: BibleStudyContext.verses(
                        in: attached.chapterVerses,
                        around: attached.verse.reference,
                        characterLimit: budget / 3
                    )
                )
            }
            let focusCharacters = focus.map { ($0.context.isEmpty ? [$0.verse] : $0.context).reduce(0) { $0 + $1.text.count } } ?? 0

            // 1. Keywords (any language → words of the version's language); optional.
            let keywordPrompt = BibleQuestionPrompt.keywords(
                for: request.question,
                previous: request.history.last,
                earlierQuestions: request.earlierQuestions,
                summary: request.summary,
                focus: focus,
                profile: profile
            )
            let suggested = (try? await streamer.response(to: keywordPrompt))
                .map(SearchKeywordParser.keywords(from:)) ?? []
            guard isCurrent() else { return }

            // 2. Retrieval: keyword ranking, fused with meaning-based ranking
            //    when available and with the verses the previous answer cited,
            //    so a follow-up like "who said it?" keeps its passage. The
            //    meaning-based query includes the previous question.
            let keywordRanked = try await bible.passages.rankedVerses(
                matching: suggested + [request.question],
                limit: Self.rankedVerseLimit
            )
            var rankings = [keywordRanked]
            var usedSemanticSearch = false
            let semanticQuery = [request.history.last?.question, request.question]
                .compactMap(\.self).joined(separator: " ")
            if let semanticSearch = engine.semanticSearch(),
               let semantic = try? await semanticSearch(semanticQuery), !semantic.isEmpty {
                guard isCurrent() else { return }
                usedSemanticSearch = true
                rankings.append(semantic)
            }
            if !request.carried.isEmpty {
                rankings.append(request.carried.map { RankedVerse(reference: $0, score: 1) })
            }
            let ranked = rankings.count == 1
                ? keywordRanked
                : RankFusion.reciprocalRank(rankings, limit: Self.rankedVerseLimit)
            let passages = try await bible.passages.passages(
                around: ranked.map(\.reference),
                window: Self.passageWindow,
                limit: Self.passageLimit,
                characterBudget: max(budget / 3, budget - focusCharacters - historyCharacters)
            )
            guard isCurrent() else { return }

            var sources = passages.compactMap { Self.range(for: $0.verses, bookName: names[$0.bookID]) }
            if let focus, let range = Self.range(for: focus.context, bookName: focus.bookName) {
                sources.insert(range, at: 0)
            }
            updateAnswer(request.messageID) {
                $0.sources = sources
                $0.usedSemanticSearch = usedSemanticSearch
            }

            // 3. Answer, streamed.
            phase = .answering
            let prompt = BibleQuestionPrompt.answer(
                question: request.question,
                passages: passages.map {
                    BibleQuestionPrompt.Passage(bookName: names[$0.bookID] ?? $0.bookID, passage: $0)
                },
                history: history,
                summary: request.summary,
                focus: focus,
                historyCharacterLimit: historyLimit,
                profile: profile
            )
            for try await delta in streamer.streamResponse(to: prompt) {
                guard isCurrent() else { return }
                updateAnswer(request.messageID) { $0.text += delta }
            }
            guard isCurrent() else { return }

            // 4. Check every citation against the Bible.
            let text = message(request.messageID)?.text ?? ""
            let grounding = Set(sources.flatMap(\.references))
            let resolved = await resolveCitations(in: text, bible: bible, books: books, names: names, grounding: grounding)
            guard isCurrent() else { return }
            citations[request.messageID] = resolved
            updateAnswer(request.messageID) { $0.status = .completed }
            phase = .idle
            await save()
            if isCurrent() { summarizeDroppedTurns() }
        } catch {
            guard request.generation == generation else { return }
            phase = .idle
            if !(Task.isCancelled || error is CancellationError) {
                updateAnswer(request.messageID) { $0.status = .failed(Self.message(for: error)) }
            }
            await save()
        }
    }

    private func message(_ id: UUID) -> ChatMessage? {
        conversation.messages.first { $0.id == id }
    }

    private func updateAnswer(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&conversation.messages[index])
    }

    private func save() async {
        await persist(stampedConversation())
    }

    private func stampedConversation() -> ChatConversation {
        conversation.updatedAt = .now
        return conversation
    }

    private func persist(_ snapshot: ChatConversation) async {
        guard !snapshot.messages.isEmpty else { return }
        try? await store.save(snapshot)
        await loadSummaries()
    }

    /// Verses the latest answer cited and that were checked against its
    /// sources, plus the verse attached to its question.
    private func carriedReferences() -> [BibleReference] {
        guard let answerIndex = conversation.messages.lastIndex(where: { $0.role == .assistant }) else { return [] }
        let answer = conversation.messages[answerIndex]
        var references: [BibleReference] = []
        if answerIndex > 0, let attached = conversation.messages[answerIndex - 1].attachedVerse?.reference {
            references.append(attached)
        }
        for citation in citations[answer.id] ?? [] {
            for item in citation.items where item.isVerified {
                if let reference = item.reference, !references.contains(reference) {
                    references.append(reference)
                }
            }
        }
        return Array(references.prefix(Self.carriedReferenceLimit))
    }

    /// Completed question/answer pairs from message `start` on, each with
    /// the message count it reaches (index after its answer).
    private static func turns(
        in messages: [ChatMessage],
        from start: Int
    ) -> [(turn: BibleQuestionPrompt.Turn, end: Int)] {
        let indices = Array(messages.indices.dropFirst(min(start, messages.count)))
        return zip(indices, indices.dropFirst()).compactMap { questionIndex, answerIndex in
            let question = messages[questionIndex]
            let answer = messages[answerIndex]
            guard question.role == .user, answer.role == .assistant, !answer.text.isEmpty else { return nil }
            if case .failed = answer.status { return nil }
            return (BibleQuestionPrompt.Turn(question: question.text, answer: answer.text), answerIndex + 1)
        }
    }

    /// At most half of the history allowance, so recent turns still fit.
    private static func summaryLimit(budget: Int) -> Int {
        min(BibleQuestionPrompt.summaryCharacterLimit, budget / 6)
    }

    /// Up to a third of the budget for earlier conversation, summary included.
    private static func historyLimit(budget: Int, summary: String?) -> Int {
        max(0, budget / 3 - (summary?.count ?? 0))
    }

    // MARK: - Summary

    /// When turns no longer fit the history budget, asks the model in the
    /// background to fold them into the conversation's summary. A question
    /// sent meanwhile uses the previous summary; a failure leaves plain
    /// trimming in place.
    private func summarizeDroppedTurns() {
        let budget = engine.passageBudget()
        let start = conversation.summarizedMessageCount ?? 0
        let all = Self.turns(in: conversation.messages, from: start)
        let kept = BibleQuestionPrompt.trimmedHistory(
            all.map(\.turn),
            characterLimit: Self.historyLimit(budget: budget, summary: conversation.historySummary)
        )
        let dropped = all.prefix(all.count - kept.count)
        guard let end = dropped.last?.end, let streamer = try? engine.makeStreamer() else { return }

        summaryTask?.cancel()
        summaryGeneration += 1
        let summaryGeneration = summaryGeneration
        let conversationID = conversation.id
        let limit = Self.summaryLimit(budget: budget)
        let prompt = BibleQuestionPrompt.summary(
            of: dropped.map(\.turn),
            previousSummary: conversation.historySummary,
            characterLimit: limit
        )

        summaryTask = Task {
            guard let text = try? await streamer.response(to: prompt) else { return }
            let summary = BibleQuestionPrompt.trimmedSummary(text, characterLimit: limit)
            guard !summary.isEmpty, !Task.isCancelled,
                  summaryGeneration == self.summaryGeneration,
                  conversation.id == conversationID,
                  (conversation.summarizedMessageCount ?? 0) == start
            else { return }
            conversation.historySummary = summary
            conversation.summarizedMessageCount = end
            await save()
        }
    }

    private func cancelSummary() {
        summaryGeneration += 1
        summaryTask?.cancel()
        summaryTask = nil
    }

    // MARK: - Citations

    private func resolveCitations(
        in text: String,
        bible: Bible,
        books: [BibleBook],
        names: [String: String],
        grounding: Set<BibleReference>
    ) async -> [ResolvedCitation] {
        var resolved: [ResolvedCitation] = []
        // Models often cite another language's book names ("John" while reading Juan).
        for citation in CitationParser.citations(in: text, books: books, aliases: BibleBookNames.aliases) {
            var items: [ResolvedCitation.Item] = []
            for item in citation.items {
                switch item {
                case let .reference(reference, endVerse):
                    let name = names[reference.bookID] ?? reference.bookID
                    let range = endVerse.map { "\(reference.verse)–\($0)" } ?? "\(reference.verse)"
                    let status: ResolvedCitation.Status
                    if Self.cited(reference, through: endVerse).allSatisfy(grounding.contains) {
                        status = .grounded
                    } else if await Self.exists(reference, through: endVerse, in: bible.verses) {
                        status = .outsideSources
                    } else {
                        status = .notFound
                    }
                    items.append(.init(
                        label: "\(name) \(reference.chapter):\(range)",
                        reference: reference,
                        status: status
                    ))
                case let .unrecognized(text):
                    items.append(.init(label: text, reference: nil, status: .notFound))
                }
            }
            resolved.append(ResolvedCitation(range: citation.range, items: items))
        }
        return resolved
    }

    private static func cited(_ reference: BibleReference, through endVerse: Int?) -> [BibleReference] {
        (reference.verse...max(reference.verse, endVerse ?? reference.verse)).compactMap {
            try? BibleReference(bookID: reference.bookID, chapter: reference.chapter, verse: $0)
        }
    }

    private static func exists(_ reference: BibleReference, through endVerse: Int?, in verses: any BibleRepository) async -> Bool {
        guard (try? await verses.verse(at: reference)) != nil else { return false }
        guard let endVerse,
              let last = try? BibleReference(bookID: reference.bookID, chapter: reference.chapter, verse: endVerse)
        else { return true }
        return (try? await verses.verse(at: last)) != nil
    }

    private static func names(for books: [BibleBook]) -> [String: String] {
        Dictionary(books.map { ($0.bookID, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The range covered by consecutive verses of one chapter.
    private static func range(for verses: [BibleVerse], bookName: String?) -> ChatVerseRange? {
        guard let first = verses.first?.reference, let last = verses.last?.reference else { return nil }
        return ChatVerseRange(
            bookID: first.bookID,
            chapter: first.chapter,
            firstVerse: first.verse,
            lastVerse: last.verse,
            bookName: bookName ?? first.bookID
        )
    }

    private static func message(for error: any Error) -> String {
        switch error as? AIEngineError {
        case .contextTooLong:
            String(localized: "The verse and chapter context are too long for the on-device model. Try a shorter question.")
        case .refused:
            String(localized: "The on-device model declined to answer this question.")
        case .unsupportedLanguage:
            String(localized: "The on-device model doesn’t support this language.")
        case .modelUnavailable:
            String(localized: "The on-device model isn’t available right now.")
        case .timedOut:
            String(localized: "The on-device model took too long to respond. Please try again.")
        case nil:
            (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
