import BibleAI
import BibleData
import BibleDomain
import CryptoKit
import Foundation
import Testing

@testable import OpenBibleAI

/// Builds and evaluates a version package's verse-embedding index
/// (`Bibles/<id>/embeddings.bin`). All are opt-in:
///
/// - `TEST_RUNNER_OPENBIBLE_VERSION=<id>` picks the package in `Bibles/`
///   (default `kjv`; build others with `Tools/BibleImport/convert_vpl.py`).
/// - `TEST_RUNNER_OPENBIBLE_BUILD_VERSE_INDEX=1` downloads/verifies the pinned
///   embedding model, embeds every verse with `MLXTextEmbedder` (the same
///   code the app uses for questions) at 512 dimensions, and writes
///   `Application Support/OpenBibleAI/<id>-verse-embeddings-512.bin` in the app
///   container (the sandboxed test host cannot write into the repository).
/// - `TEST_RUNNER_OPENBIBLE_EVAL_RETRIEVAL=1` compares keyword, semantic and
///   hybrid retrieval on golden questions (English and Spanish) at 256 and 512
///   dimensions and prints recall.
@MainActor
struct VerseIndexBuilderTests {
    nonisolated private static let build = ProcessInfo.processInfo.environment["OPENBIBLE_BUILD_VERSE_INDEX"] == "1"
    nonisolated private static let evaluate = ProcessInfo.processInfo.environment["OPENBIBLE_EVAL_RETRIEVAL"] == "1"
    nonisolated private static let export = ProcessInfo.processInfo.environment["OPENBIBLE_EXPORT_VERSE_INDEX"] == "1"
    nonisolated static let versionID = ProcessInfo.processInfo.environment["OPENBIBLE_VERSION"] ?? "kjv"
    nonisolated static var package: URL {
        RepositoryBibles.kjv.deletingLastPathComponent().appendingPathComponent(versionID, isDirectory: true)
    }

    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("OpenBibleAI", isDirectory: true)
    }
    static var builtIndexURL: URL {
        supportDirectory.appendingPathComponent("\(versionID)-verse-embeddings-512.bin")
    }
    static var embedderDirectory: URL {
        supportDirectory.appendingPathComponent("Models/embedding", isDirectory: true)
    }

    private func loadBible() async throws -> (JSONBibleRepository, [BibleBook], Data) {
        let package = try await BibleVersionPackage.load(from: Self.package)
        let versesURL = Self.package.appendingPathComponent(BibleVersionPackage.FileName.verses)
        return (package.repository, package.books, try Data(contentsOf: versesURL))
    }

    private func embedder() async throws -> MLXTextEmbedder {
        let store = LocalModelStore(manifest: .qwen3Embedding, directory: Self.embedderDirectory)
        if await !store.isInstalled() { try await store.download { _ in } }
        return MLXTextEmbedder(directory: Self.embedderDirectory, dimensions: 512)
    }

    @Test(.enabled(if: VerseIndexBuilderTests.build))
    func buildVerseIndex() async throws {
        let (repository, books, versesData) = try await loadBible()
        var verses: [BibleVerse] = []
        for book in books {
            for chapter in try await repository.chapters(in: book.bookID) {
                verses += try await repository.verses(in: book.bookID, chapter: chapter)
            }
        }
        #expect(verses.count == (Self.versionID == "kjv" ? 31_102 : verses.count))
        print("Embedding \(verses.count) verses of \(Self.versionID)")

        let embedder = try await embedder()
        let clock = ContinuousClock()
        let start = clock.now
        var entries: [(BibleReference, [Float])] = []
        entries.reserveCapacity(verses.count)
        let batchSize = 64
        for batchStart in stride(from: 0, to: verses.count, by: batchSize) {
            let batch = Array(verses[batchStart..<min(batchStart + batchSize, verses.count)])
            let vectors = try await embedder.embedDocuments(batch.map(\.text))
            entries += zip(batch.map(\.reference), vectors).map { ($0, $1) }
        }
        let elapsed = clock.now - start

        let source = SHA256.hash(data: versesData).map { String(format: "%02x", $0) }.joined()
        let header = VerseVectorIndex.Header(
            model: ModelManifest.qwen3Embedding.repository,
            revision: ModelManifest.qwen3Embedding.revision,
            dimensions: 512, count: entries.count, source: source
        )
        let data = try VerseVectorIndex.encode(header: header, entries: entries)
        try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        try data.write(to: Self.builtIndexURL)

        print("\n=== OPENBIBLE VERSE INDEX BUILT ===\n\(Self.builtIndexURL.path)\nverses: \(entries.count), bytes: \(data.count), embedding time: \(elapsed)\n=== END ===\n")
        await embedder.unload()
    }

    /// `TEST_RUNNER_OPENBIBLE_EXPORT_VERSE_INDEX=1`: writes the package index
    /// (truncated to the app's dimensions) next to the 512-d build; copy it
    /// to `Bibles/<id>/embeddings.bin`.
    @Test(.enabled(if: VerseIndexBuilderTests.export))
    func exportBundledIndex() throws {
        let full = try VerseVectorIndex(data: Data(contentsOf: Self.builtIndexURL))
        let bundled = try full.truncated(to: MLXTextEmbedder.defaultDimensions)
        let destination = Self.supportDirectory.appendingPathComponent("\(Self.versionID)-embeddings.bin")
        let data = try VerseVectorIndex.encode(
            header: bundled.header,
            entries: (0..<bundled.header.count).map { bundled.entry(at: $0) }
        )
        try data.write(to: destination)
        print("\n=== OPENBIBLE BUNDLED INDEX ===\n\(destination.path)\nbytes: \(data.count)\n=== END ===\n")
    }

    /// The app's runtime embedder must reproduce the bundled vectors, or
    /// question and verse vectors would not be comparable.
    @Test(.enabled(if: VerseIndexBuilderTests.evaluate))
    func bundledIndexMatchesRuntimeEmbedder() async throws {
        let (repository, _, _) = try await loadBible()
        let url = Self.package.appendingPathComponent(BibleVersionPackage.FileName.embeddings)
        let bundled = try VerseVectorIndex(data: Data(contentsOf: url))
        let embedder = MLXTextEmbedder(directory: Self.embedderDirectory, dimensions: bundled.header.dimensions)

        var worst: Float = 1
        for row in [0, 1_234, 15_000, 23_145, 31_101] {
            let (reference, stored) = bundled.entry(at: row)
            let verse = try await repository.verse(at: reference)
            let fresh = try await embedder.embedDocuments([verse.text])[0]
            let cosine = zip(stored, fresh).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            worst = min(worst, cosine)
        }
        print("\n=== OPENBIBLE INDEX/EMBEDDER CONSISTENCY: worst cosine \(worst) ===\n")
        #expect(worst >= 0.99)
        await embedder.unload()
    }

    struct Golden: Sendable {
        let question: String
        let expected: [String]  // "BOOK chapter:first-last"
    }

    static let golden: [Golden] = [
        .init(question: "Where was Jesus born?", expected: ["MAT 2:1-6", "LUK 2:4-7"]),
        .init(question: "¿Dónde nació Jesús?", expected: ["MAT 2:1-6", "LUK 2:4-7"]),
        .init(question: "Where did Jesus heal a blind person?", expected: ["JOH 9:1-41", "MAR 10:46-52", "MAR 8:22-26", "MAT 9:27-30", "MAT 20:29-34", "LUK 18:35-43"]),
        .init(question: "¿Dónde sanó Jesús a un ciego?", expected: ["JOH 9:1-41", "MAR 10:46-52", "MAR 8:22-26", "MAT 9:27-30", "MAT 20:29-34", "LUK 18:35-43"]),
        .init(question: "What does the Bible say about forgiving others?", expected: ["MAT 6:12-15", "MAT 18:21-35", "MAR 11:25-26", "LUK 17:3-4", "EPH 4:32-32", "COL 3:13-13"]),
        .init(question: "¿Qué dice la Biblia sobre perdonar a los demás?", expected: ["MAT 6:12-15", "MAT 18:21-35", "MAR 11:25-26", "LUK 17:3-4", "EPH 4:32-32", "COL 3:13-13"]),
        .init(question: "How did Jesus feed five thousand people?", expected: ["MAT 14:15-21", "MAR 6:35-44", "LUK 9:12-17", "JOH 6:5-13"]),
        .init(question: "¿Cómo alimentó Jesús a cinco mil personas?", expected: ["MAT 14:15-21", "MAR 6:35-44", "LUK 9:12-17", "JOH 6:5-13"]),
        .init(question: "How did Moses cross the Red Sea?", expected: ["EXO 14:16-29"]),
        .init(question: "¿Cómo cruzó Moisés el Mar Rojo?", expected: ["EXO 14:16-29"]),
        .init(question: "Who betrayed Jesus?", expected: ["MAT 26:14-16", "MAT 26:47-50", "MAR 14:10-11", "LUK 22:3-6", "LUK 22:47-48", "JOH 18:2-5"]),
        .init(question: "What is love according to Paul?", expected: ["1CO 13:4-8"]),
    ]

    private func found(_ passages: [BiblePassage], _ expected: [String]) -> Bool {
        expected.contains { range in
            let parts = range.split(separator: " ")
            let cv = parts[1].split(separator: ":")
            let bounds = cv[1].split(separator: "-").map { Int($0)! }
            return passages.contains { passage in
                passage.bookID == String(parts[0]) && passage.chapter == Int(cv[0])!
                    && passage.verses.contains { (bounds[0]...bounds[1]).contains($0.reference.verse) }
            }
        }
    }

    @Test(.enabled(if: VerseIndexBuilderTests.evaluate))
    func evaluateRetrieval() async throws {
        let (repository, _, _) = try await loadBible()
        let index512 = try VerseVectorIndex(data: Data(contentsOf: Self.builtIndexURL))
        let index256 = try index512.truncated(to: 256)
        let embedder = try await embedder()

        func passages(_ ranked: [RankedVerse]) async throws -> [BiblePassage] {
            try await repository.passages(around: ranked.map(\.reference), window: 2, limit: 6, characterBudget: 6_000)
        }

        var hits: [String: Int] = [:]
        var lines: [String] = []
        for golden in Self.golden {
            let keyword = try await repository.rankedVerses(matching: [golden.question], limit: 20)
            let query = try await embedder.embedQuery(golden.question)
            let semantic512 = index512.search(query, limit: 20)
            let semantic256 = index256.search(Array(query.prefix(256)), limit: 20)
            let results: [(String, [RankedVerse])] = [
                ("keyword", keyword),
                ("semantic256", semantic256),
                ("semantic512", semantic512),
                ("hybrid256", RankFusion.reciprocalRank([keyword, semantic256], limit: 20)),
                ("hybrid512", RankFusion.reciprocalRank([keyword, semantic512], limit: 20)),
            ]
            var row = golden.question
            for (name, ranked) in results {
                let ok = found(try await passages(ranked), golden.expected)
                hits[name, default: 0] += ok ? 1 : 0
                row += "  \(name):\(ok ? "✓" : "✗")"
            }
            lines.append(row)
        }
        let total = Self.golden.count
        let summary = ["keyword", "semantic256", "semantic512", "hybrid256", "hybrid512"]
            .map { "\($0) \(hits[$0, default: 0])/\(total)" }.joined(separator: ", ")
        print("\n=== OPENBIBLE RETRIEVAL EVAL (question words only, no model keywords) ===\n\(lines.joined(separator: "\n"))\n\(summary)\n=== END ===\n")
        await embedder.unload()
    }
}
