import BibleAI
import BibleData
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

/// Real MLX check, separate from the mocked tests: downloads the pinned model
/// (verifying SHA-256), loads it with MLX and streams an answer using real KJV
/// chapter context. Skipped unless `OPENBIBLE_LIVE_MLX=standard|compact`
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

        let versesURL = try #require(Bundle.main.url(forResource: "kjv-verses", withExtension: "json"))
        let booksURL = try #require(Bundle.main.url(forResource: "kjv-books", withExtension: "json"))
        let catalog = try await JSONBibleBookCatalog.load(from: booksURL)
        let repository = try await JSONBibleRepository.load(from: versesURL, books: catalog.books)
        let chapter = try await repository.verses(in: "JOH", chapter: 3)
        let selected = try #require(chapter.first { $0.reference.verse == 16 })

        let engine = MLXModelEngine(directory: directory)
        let loadStart = clock.now
        try await engine.prepare()
        let loadTime = clock.now - loadStart

        let model = StudyAssistantModel(
            provider: MLXModelProvider(engine: engine, maximumResponseTokens: tier.maximumResponseTokens)
        )
        let answerStart = clock.now
        await model.ask(
            verse: selected,
            bookName: "John",
            chapterVerses: chapter,
            question: "In one or two sentences, what does this verse say about God's motive?"
        )
        let answerTime = clock.now - answerStart

        print("""

        === OPENBIBLE LIVE MLX (\(tier.displayName)) ===
        download/verify: \(downloadTime), load: \(loadTime), answer: \(answerTime)
        state: \(model.state)
        \(model.answer)
        === END ===

        """)

        #expect(model.state == .completed)
        #expect(!model.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!model.answer.contains("<think>"))
        await engine.unload()
    }
}
