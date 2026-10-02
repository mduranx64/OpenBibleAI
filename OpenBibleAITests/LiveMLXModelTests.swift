import BibleAI
import BibleData
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

/// Real MLX check, separate from the mocked tests: downloads the pinned model
/// (verifying SHA-256), loads it with MLX and streams an answer using real KJV
/// chapter context through the chat (verse attached). Skipped unless `OPENBIBLE_LIVE_MLX=standard|compact`
/// (forward with `TEST_RUNNER_OPENBIBLE_LIVE_MLX=…`). The model is stored
/// where the app keeps it, so the app can reuse it. Prints the answer for a
/// human to read; asserts only that it streams without a think block.
@MainActor
struct LiveMLXModelTests {
    nonisolated private static let tierName =
        ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_MLX"]

    @Test(.enabled(if: LiveMLXModelTests.tierName != nil))
    func downloadedModelStreamsAnAnswerWithChapterContext() async throws {
        let tier = try #require(MLXModelTier(rawValue: Self.tierName ?? ""))
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("OpenBibleAI/Models/\(tier.rawValue)", isDirectory: true)
        let store = LocalModelStore(manifest: tier.manifest, directory: directory)

        let clock = ContinuousClock()
        let downloadStart = clock.now
        if await !store.isInstalled() {
            try await store.download { _ in }
        }
        let downloadTime = clock.now - downloadStart
        #expect(await store.isInstalled())

        let versesURL = RepositoryBibles.kjvVerses
        let booksURL = RepositoryBibles.kjvBooks
        let catalog = try await JSONBibleBookCatalog.load(from: booksURL)
        let repository = try await JSONBibleRepository.load(from: versesURL, books: catalog.books)
        let chapter = try await repository.verses(in: "JOH", chapter: 3)
        let selected = try #require(chapter.first { $0.reference.verse == 16 })

        let engine = MLXModelEngine(directory: directory)
        let loadStart = clock.now
        try await engine.prepare()
        let loadTime = clock.now - loadStart

        let provider = MLXModelProvider(engine: engine, maximumResponseTokens: tier.maximumResponseTokens)
        let model = BibleChatModel(
            passages: repository,
            verses: repository,
            books: { catalog.books },
            engine: .init(makeStreamer: { provider }, passageBudget: { tier.contextCharacterLimit }),
            store: InMemoryChatStore()
        )
        model.attach(verse: selected, bookName: "John", chapterVerses: chapter)
        let answerStart = clock.now
        await model.send("In one or two sentences, what does this verse say about God's motive?").value
        let answerTime = clock.now - answerStart
        let answer = try #require(model.conversation.messages.last)

        print("""

        === OPENBIBLE LIVE MLX (\(tier.displayName)) ===
        download/verify: \(downloadTime), load: \(loadTime), answer: \(answerTime)
        status: \(answer.status)
        \(answer.text)
        === END ===

        """)

        #expect(answer.status == .completed)
        #expect(!answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!answer.text.contains("<think>"))
        await engine.unload()
    }
}
