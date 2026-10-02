import BibleAI
import BibleDomain
import Foundation
import Observation

/// The optional "Improve search" download: a multilingual embedding model
/// that, with the bundled verse vectors, adds meaning-based retrieval to
/// "Ask the Bible". Keyword retrieval works without it.
@MainActor
@Observable
final class SemanticSearchModel {
    typealias DownloadState = AIEngineModel.DownloadState

    private(set) var isInstalled = false
    private(set) var downloadState: DownloadState = .idle
    /// Apple silicon with enough memory (same rule as the downloadable chat models).
    let isSupported: Bool

    @ObservationIgnored private let store: (any LocalModelStoring)?
    @ObservationIgnored private let indexURL: URL?
    @ObservationIgnored private let makeEmbedder: @MainActor (URL) -> (any QueryEmbedding)?
    @ObservationIgnored private var search: SemanticVerseSearch?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadGeneration = 0

    init(
        store: (any LocalModelStoring)?,
        isSupported: Bool,
        indexURL: URL?,
        makeEmbedder: @escaping @MainActor (URL) -> (any QueryEmbedding)?
    ) {
        self.store = store
        self.isSupported = isSupported
        self.indexURL = indexURL
        self.makeEmbedder = makeEmbedder
    }

    static func live() -> SemanticSearchModel {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("OpenBibleAI/Models/embedding", isDirectory: true)
        return SemanticSearchModel(
            store: LocalModelStore(manifest: .qwen3Embedding, directory: directory),
            isSupported: MLXModelTier.current != nil,
            indexURL: Bundle.main.url(forResource: "kjv-verse-embeddings", withExtension: "bin"),
            makeEmbedder: { MLXTextEmbedder(directory: $0) }
        )
    }

    /// The download is offered only where it can run and the index is bundled.
    var isOffered: Bool {
        isSupported && store != nil && indexURL != nil
    }

    var downloadSizeText: String {
        ByteCountFormatter.string(fromByteCount: ModelManifest.qwen3Embedding.totalBytes, countStyle: .file)
    }

    func refresh() async {
        isInstalled = await store?.isInstalled() ?? false
    }

    /// Ranking for a question, or nil when semantic search can't be used.
    func searcher() -> (@Sendable (String) async throws -> [RankedVerse])? {
        guard isOffered, isInstalled, let store, let indexURL else { return nil }
        if search == nil, let embedder = makeEmbedder(store.directory) {
            search = SemanticVerseSearch(indexURL: indexURL, embedder: embedder)
        }
        guard let search else { return nil }
        return { question in
            try await search.rankedVerses(for: question, limit: BibleChatModel.rankedVerseLimit)
        }
    }

    /// Frees the embedding model and vectors (e.g. in the background).
    func unload() {
        guard let search else { return }
        Task { await search.unload() }
    }

    // MARK: - Download

    @discardableResult
    func startDownload() -> Task<Void, Never> {
        if let downloadTask { return downloadTask }
        guard let store else { return Task {} }

        downloadGeneration += 1
        let generation = downloadGeneration
        downloadState = .downloading(0)

        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.reportProgress(fraction, generation: generation) }
        }

        let task = Task { [weak self] in
            var outcome = DownloadState.idle
            do {
                try await store.download(progress: report)
            } catch is CancellationError {
                outcome = .idle
            } catch {
                outcome = .failed("The download failed: \(error.localizedDescription)")
            }
            guard let self, generation == self.downloadGeneration else { return }
            self.downloadState = outcome
            self.downloadTask = nil
            await self.refresh()
        }
        downloadTask = task
        return task
    }

    func cancelDownload() {
        downloadGeneration += 1
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
    }

    func deleteModel() async {
        cancelDownload()
        if let search {
            await search.unload()
            self.search = nil
        }
        try? await store?.delete()
        await refresh()
    }

    private func reportProgress(_ fraction: Double, generation: Int) {
        guard generation == downloadGeneration,
              case let .downloading(current) = downloadState,
              fraction >= current
        else { return }
        downloadState = .downloading(fraction)
    }
}
