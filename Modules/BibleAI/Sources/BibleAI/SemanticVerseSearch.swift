//
//  SemanticVerseSearch.swift
//  BibleAI
//

import BibleDomain
import Foundation

/// Embeds a question for semantic search. `MLXTextEmbedder` in the app;
/// fakes in tests.
public protocol QueryEmbedding: Sendable {
    func embedQuery(_ question: String) async throws -> [Float]
    func unload() async
}

extension MLXTextEmbedder: QueryEmbedding {}

/// Meaning-based verse ranking: the question is embedded on device and
/// compared with the bundled verse vectors. The index is loaded lazily and
/// must come from the same pinned embedding model, or the vectors would not
/// be comparable.
public actor SemanticVerseSearch {
    public enum SearchError: Error, Equatable, Sendable {
        case indexModelMismatch
    }

    private let indexURL: URL
    private let embedder: any QueryEmbedding
    private let expectedModel: String
    private let expectedRevision: String
    private var index: VerseVectorIndex?

    public init(
        indexURL: URL,
        embedder: any QueryEmbedding,
        manifest: ModelManifest = .qwen3Embedding
    ) {
        self.indexURL = indexURL
        self.embedder = embedder
        self.expectedModel = manifest.repository
        self.expectedRevision = manifest.revision
    }

    public func rankedVerses(for question: String, limit: Int) async throws -> [RankedVerse] {
        let index = try await loadedIndex()
        let query = try await embedder.embedQuery(question)
        try Task.checkCancellation()
        return index.search(query, limit: limit)
    }

    /// Frees the embedding model and the loaded vectors.
    public func unload() async {
        index = nil
        await embedder.unload()
    }

    private func loadedIndex() async throws -> VerseVectorIndex {
        if let index { return index }
        let loaded = try await Self.load(indexURL)
        guard loaded.header.model == expectedModel, loaded.header.revision == expectedRevision else {
            throw SearchError.indexModelMismatch
        }
        index = loaded
        return loaded
    }

    /// Reads and converts ~16 MB off the caller's actor.
    @concurrent
    private static func load(_ url: URL) async throws -> VerseVectorIndex {
        try VerseVectorIndex(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}
