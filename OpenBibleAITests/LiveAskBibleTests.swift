import BibleAI
import BibleData
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

/// Real Bible chat runs, separate from the mocked tests. Skipped unless
/// `OPENBIBLE_LIVE_ASK=apple|standard|compact` (forward with
/// `TEST_RUNNER_OPENBIBLE_LIVE_ASK=…`); MLX tiers need the downloaded model.
/// Prints keywords, sources, answers and citation checks for a human to read;
/// asserts only that each answer completes.
@MainActor
struct LiveAskBibleTests {
    nonisolated private static let engineName =
        ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_ASK"]

    static let questions = [
        "Where was Jesus born?",
        "Where did Jesus heal a blind person?",
        "¿Dónde nació Jesús?",
        "¿Dónde sanó Jesús a un ciego?",
        "What is love according to Paul?",
        "¿Qué dice la Biblia sobre perdonar a los demás?",
    ]

    nonisolated private static let useSemantic =
        ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_ASK_SEMANTIC"] == "1"

    @Test(.enabled(if: LiveAskBibleTests.engineName != nil))
    func answersCiteVerifiedVerses() async throws {
        let (model, _) = try await makeModel()

        var report = "\n=== OPENBIBLE LIVE ASK (\(Self.engineName ?? "")\(Self.useSemantic ? " + semantic" : "")) ===\n"
        for question in Self.questions {
            model.newChat()
            report += try await ask(question, model)
        }
        print(report + "=== END ===\n")
    }

    /// Follow-ups that only make sense with the earlier turns, in English,
    /// and in Spanish about an attached verse.
    @Test(.enabled(if: LiveAskBibleTests.engineName != nil))
    func conversationsKeepContextAcrossTurns() async throws {
        let (model, repository) = try await makeModel()
        var report = "\n=== OPENBIBLE LIVE CHAT (\(Self.engineName ?? "")\(Self.useSemantic ? " + semantic" : "")) ===\n"

        model.newChat()
        for question in ["Where was Jesus born?", "Who was king then?", "Where did his family flee afterwards?"] {
            report += try await ask(question, model)
        }

        model.newChat()
        let chapter = try await repository.verses(in: "JOH", chapter: 3)
        let verse = try #require(chapter.first { $0.reference.verse == 16 })
        model.attach(verse: verse, bookName: "John", chapterVerses: chapter)
        report += "[attached John 3:16]\n"
        for question in ["¿Qué significa este versículo?", "¿Quién dijo estas palabras?", "¿A quién se las dijo?"] {
            report += try await ask(question, model)
        }
        print(report + "=== END ===\n")
    }

    private func ask(_ question: String, _ model: BibleChatModel) async throws -> String {
        let clock = ContinuousClock()
        let start = clock.now
        await model.send(question).value
        let answer = try #require(model.conversation.messages.last)
        let items = (model.citations[answer.id] ?? []).flatMap(\.items)
        #expect(answer.status == .completed, "\(question)")
        // Answer quality varies by model; the report shows it. Only completion is asserted.
        return """
        Q: \(question)  [\(clock.now - start)]
          sources: \(answer.sources.map(\.title).joined(separator: "; "))\(answer.usedSemanticSearch ? "  [+semantic]" : "")
          answer: \(answer.text.replacingOccurrences(of: "\n", with: " "))
          citations: \(items.map { "\($0.label)\($0.isVerified ? " ✓" : " ✗")" }.joined(separator: ", "))

        """
    }

    private func makeModel() async throws -> (BibleChatModel, JSONBibleRepository) {
        let booksURL = try #require(Bundle.main.url(forResource: "kjv-books", withExtension: "json"))
        let versesURL = try #require(Bundle.main.url(forResource: "kjv-verses", withExtension: "json"))
        let catalog = try await JSONBibleBookCatalog.load(from: booksURL)
        let repository = try await JSONBibleRepository.load(from: versesURL, books: catalog.books)

        let streamer: any AIPromptStreaming
        let budget: Int
        switch Self.engineName {
        case "apple":
            streamer = AppleFoundationModelProvider()
            budget = BibleStudyContext.defaultCharacterLimit
        default:
            let tier = try #require(MLXModelTier(rawValue: Self.engineName ?? ""))
            let directory = URL.applicationSupportDirectory
                .appendingPathComponent("OpenBibleAI/Models/\(tier.rawValue)", isDirectory: true)
            streamer = MLXModelProvider(
                engine: MLXModelEngine(directory: directory),
                maximumResponseTokens: tier.maximumResponseTokens
            )
            budget = tier.contextCharacterLimit
        }

        var semantic: SemanticVerseSearch?
        if Self.useSemantic {
            let indexURL = try #require(Bundle.main.url(forResource: "kjv-verse-embeddings", withExtension: "bin"))
            let embedderDirectory = URL.applicationSupportDirectory
                .appendingPathComponent("OpenBibleAI/Models/embedding", isDirectory: true)
            semantic = SemanticVerseSearch(indexURL: indexURL, embedder: MLXTextEmbedder(directory: embedderDirectory))
        }
        let searcher: (@Sendable (String) async throws -> [RankedVerse])? = semantic.map { search in
            { question in try await search.rankedVerses(for: question, limit: 20) }
        }

        let model = BibleChatModel(
            passages: repository,
            verses: repository,
            books: { catalog.books },
            engine: .init(makeStreamer: { streamer }, passageBudget: { budget }, semanticSearch: { searcher }),
            store: InMemoryChatStore()
        )

        return (model, repository)
    }
}
