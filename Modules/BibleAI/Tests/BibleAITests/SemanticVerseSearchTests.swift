//
//  SemanticVerseSearchTests.swift
//  BibleAI
//

import Foundation
import Testing
import BibleDomain

@testable import BibleAI

struct SemanticVerseSearchTests {
    private func indexURL(model: String = ModelManifest.qwen3Embedding.repository,
                          revision: String = ModelManifest.qwen3Embedding.revision) throws -> URL {
        let entries: [(BibleReference, [Float])] = [
            (try BibleReference(bookID: "MAT", chapter: 2, verse: 1), [1, 0]),
            (try BibleReference(bookID: "JOH", chapter: 9, verse: 7), [0, 1]),
        ]
        let data = try VerseVectorIndex.encode(
            header: .init(model: model, revision: revision, dimensions: 2, count: 2, source: "sha"),
            entries: entries
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }

    @Test
    func embedsTheQuestionAndRanksVersesByMeaning() async throws {
        let url = try indexURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let embedder = FakeEmbedder(vector: [0.1, 0.9])
        let search = SemanticVerseSearch(indexURL: url, embedder: embedder)

        let ranked = try await search.rankedVerses(for: "¿Dónde sanó Jesús a un ciego?", limit: 2)

        #expect(ranked.first?.reference == (try BibleReference(bookID: "JOH", chapter: 9, verse: 7)))
        #expect(embedder.questions == ["¿Dónde sanó Jesús a un ciego?"])
    }

    @Test
    func indexBuiltByAnotherModelIsRejected() async throws {
        let url = try indexURL(revision: "different")
        defer { try? FileManager.default.removeItem(at: url) }
        let search = SemanticVerseSearch(indexURL: url, embedder: FakeEmbedder(vector: [1, 0]))

        await #expect(throws: SemanticVerseSearch.SearchError.indexModelMismatch) {
            _ = try await search.rankedVerses(for: "Q", limit: 1)
        }
    }
}

private final class FakeEmbedder: QueryEmbedding, @unchecked Sendable {
    private let lock = NSLock()
    private let vector: [Float]
    private var asked: [String] = []

    init(vector: [Float]) { self.vector = vector }

    var questions: [String] { lock.withLock { asked } }

    func embedQuery(_ question: String) async throws -> [Float] {
        lock.withLock { asked.append(question) }
        return vector
    }

    func unload() async {}
}
