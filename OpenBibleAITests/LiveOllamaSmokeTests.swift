import BibleAI
import BibleData
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

/// Real installed-model smoke check, kept separate from the mocked provider
/// and model tests. It needs a running local Ollama with at least one model.
///
/// Skipped unless `OPENBIBLE_LIVE_OLLAMA=1` (forward it to the test host with
/// `TEST_RUNNER_OPENBIBLE_LIVE_OLLAMA=1`). It proves the end-to-end path
/// streams a non-empty answer using real chapter context; it does not judge
/// answer quality or accuracy, so the text is printed for a human to read.
@MainActor
struct LiveOllamaSmokeTests {
    // `nonisolated`: read by the `.enabled(if:)` trait outside the main actor.
    nonisolated private static let enabled =
        ProcessInfo.processInfo.environment["OPENBIBLE_LIVE_OLLAMA"] == "1"

    @Test(.enabled(if: LiveOllamaSmokeTests.enabled))
    func realModelStreamsAnAnswerWithChapterContext() async throws {
        let booksURL = try #require(
            Bundle.main.url(forResource: "kjv-books", withExtension: "json")
        )
        let versesURL = try #require(
            Bundle.main.url(forResource: "kjv-verses", withExtension: "json")
        )
        let catalog = try await JSONBibleBookCatalog.load(from: booksURL)
        let repository = try await JSONBibleRepository.load(
            from: versesURL,
            books: catalog.books
        )

        let chapter = try await repository.verses(in: "JOH", chapter: 3)
        let selected = try #require(
            chapter.first { $0.reference.verse == 16 }
        )
        let context = BibleStudyContext.verses(
            in: chapter,
            around: selected.reference
        )

        let models = try await OllamaModelCatalog().models()
        let modelName = try #require(
            models.map(\.name).sorted().first,
            "No installed Ollama model found"
        )

        let model = StudyAssistantModel(
            provider: OllamaProvider(model: modelName)
        )

        let clock = ContinuousClock()
        let start = clock.now
        await model.ask(
            verse: selected,
            bookName: "John",
            chapterVerses: chapter,
            question: "In one or two sentences, what does this verse say about God's motive?"
        )
        let elapsed = clock.now - start

        print("""

        === OPENBIBLE LIVE OLLAMA SMOKE ===
        model: \(modelName)
        context verses sent: \(context.count) of \(chapter.count)
        elapsed: \(elapsed)
        state: \(model.state)
        answer for \(model.answerReference.map { "\($0.bookID) \($0.chapter):\($0.verse)" } ?? "none"):
        \(model.answer)
        === END SMOKE ===

        """)

        #expect(model.state == .completed)
        #expect(!model.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(model.answerReference == selected.reference)
    }
}
