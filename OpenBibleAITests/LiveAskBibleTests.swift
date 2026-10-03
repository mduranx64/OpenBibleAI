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
/// asserts only that each answer completes. `OPENBIBLE_VERSION=<id>` answers
/// from `Bibles/<id>` (default `kjv`; semantic search uses its index).
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
        "Onde Jesus nasceu?",
        "O que é o amor segundo Paulo?",
    ]

    nonisolated private static let useSemantic =
        ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_ASK_SEMANTIC"] == "1"

    @Test(.enabled(if: LiveAskBibleTests.engineName != nil))
    func answersCiteVerifiedVerses() async throws {
        let (model, _) = try await makeModel()

        var report = "\n=== OPENBIBLE LIVE ASK (\(VerseIndexBuilderTests.versionID), \(Self.engineName ?? "")\(Self.useSemantic ? " + semantic" : "")) ===\n"
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
        let john = try await repository.books().first { $0.bookID == "JOH" }?.name ?? "John"
        model.attach(verse: verse, bookName: john, chapterVerses: chapter)
        report += "[attached \(john) 3:16]\n"
        for question in ["¿Qué significa este versículo?", "¿Quién dijo estas palabras?", "¿A quién se las dijo?"] {
            report += try await ask(question, model)
        }
        print(report + "=== END ===\n")
    }

    /// A long chat whose last question refers to the first one, which by
    /// then has dropped out of the history and survives only in the summary.
    @Test(.enabled(if: LiveAskBibleTests.engineName != nil))
    func longChatsRememberEarlyTurnsThroughTheSummary() async throws {
        // Half the engine's budget (the compact model's), so early turns are
        // summarized within six questions.
        let (model, _) = try await makeModel(budgetDivisor: 2)
        var report = "\n=== OPENBIBLE LIVE LONG CHAT (\(Self.engineName ?? "")\(Self.useSemantic ? " + semantic" : "")) ===\n"
        model.newChat()
        for question in [
            "Who was Moses' brother?",
            "Where was Jesus born?",
            "Who was king then?",
            "What did the wise men bring?",
            "Where did the family flee?",
            "Going back to my first question: what did that brother make while Moses was on the mountain?",
        ] {
            report += try await ask(question, model)
            await model.summaryTask?.value
            report += "  [summary covers \(model.conversation.summarizedMessageCount ?? 0) messages: \(model.conversation.historySummary ?? "none")]\n\n"
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
          status: \(answer.status)

        """
    }

    private func makeModel(budgetDivisor: Int = 1) async throws -> (BibleChatModel, JSONBibleRepository) {
        let package = try await BibleVersionPackage.load(from: VerseIndexBuilderTests.package)
        let repository = package.repository

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
            let indexURL = try #require(package.embeddingsURL)
            let embedderDirectory = URL.applicationSupportDirectory
                .appendingPathComponent("OpenBibleAI/Models/embedding", isDirectory: true)
            semantic = SemanticVerseSearch(indexURL: indexURL, embedder: MLXTextEmbedder(directory: embedderDirectory))
        }
        let searcher: (@Sendable (String) async throws -> [RankedVerse])? = semantic.map { search in
            { question in try await search.rankedVerses(for: question, limit: 20) }
        }

        let bible = BibleChatModel.Bible(
            version: package.version,
            passages: repository,
            verses: repository,
            books: { package.books }
        )
        let model = BibleChatModel(
            bible: { _ in bible },
            engine: .init(makeStreamer: { streamer }, passageBudget: { budget / budgetDivisor }, semanticSearch: { searcher }),
            store: InMemoryChatStore()
        )

        return (model, repository)
    }
}
