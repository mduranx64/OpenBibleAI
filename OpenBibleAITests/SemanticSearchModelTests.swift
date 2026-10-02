import BibleAI
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

@MainActor
struct SemanticSearchModelTests {
    @Test
    func searchIsOfferedOnlyWhenSupportedAndInstalled() async throws {
        let unsupported = SemanticSearchModel(store: nil, isSupported: false, indexURL: nil, makeEmbedder: { _ in nil })
        await unsupported.refresh()
        #expect(unsupported.searcher() == nil)
        #expect(!unsupported.isOffered)

        let store = FakeSearchStore(installed: false)
        let model = SemanticSearchModel(store: store, isSupported: true, indexURL: URL(fileURLWithPath: "/tmp/index.bin"), makeEmbedder: { _ in nil })
        await model.refresh()
        #expect(model.isOffered)
        #expect(!model.isInstalled)
        #expect(model.searcher() == nil)
    }

    @Test
    func downloadInstallsTheModelAndEnablesSearch() async throws {
        let store = FakeSearchStore(installed: false)
        let model = SemanticSearchModel(
            store: store, isSupported: true,
            indexURL: URL(fileURLWithPath: "/tmp/index.bin"),
            makeEmbedder: { _ in NullEmbedder() }
        )
        await model.refresh()

        await model.startDownload().value

        #expect(model.downloadState == .idle)
        #expect(model.isInstalled)
        #expect(model.searcher() != nil)
    }

    @Test
    func failedDownloadShowsAMessageAndDeleteUninstalls() async throws {
        let failing = SemanticSearchModel(
            store: FakeSearchStore(installed: false, failure: URLError(.notConnectedToInternet)),
            isSupported: true, indexURL: URL(fileURLWithPath: "/tmp/index.bin"), makeEmbedder: { _ in nil }
        )
        await failing.refresh()
        await failing.startDownload().value
        guard case .failed = failing.downloadState else {
            Issue.record("Expected failure, got \(failing.downloadState)")
            return
        }

        let installed = FakeSearchStore(installed: true)
        let model = SemanticSearchModel(store: installed, isSupported: true, indexURL: URL(fileURLWithPath: "/tmp/index.bin"), makeEmbedder: { _ in NullEmbedder() })
        await model.refresh()
        #expect(model.isInstalled)
        await model.deleteModel()
        #expect(!model.isInstalled)
    }

    @Test
    func searchUsesTheReadingVersionsIndexOnlyWhenItHasOne() async {
        let model = SemanticSearchModel(store: FakeSearchStore(installed: true), isSupported: true, indexURL: nil, makeEmbedder: { _ in NullEmbedder() })
        await model.refresh()
        #expect(model.isOffered, "The model download is offered before a version is loaded")
        #expect(model.searcher() == nil, "No index: no semantic search")

        model.useIndex(URL(fileURLWithPath: "/tmp/kjv/embeddings.bin"))
        #expect(model.searcher() != nil)

        model.useIndex(nil)
        #expect(model.searcher() == nil)
    }
}

private final class FakeSearchStore: LocalModelStoring, @unchecked Sendable {
    let directory = URL(fileURLWithPath: "/tmp/fake-embedding")
    private let lock = NSLock()
    private var installed: Bool
    private let failure: (any Error)?

    init(installed: Bool, failure: (any Error)? = nil) {
        self.installed = installed
        self.failure = failure
    }

    func isInstalled() async -> Bool { lock.withLock { installed } }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        if let failure { throw failure }
        lock.withLock { installed = true }
        progress(1)
    }

    func delete() async throws { lock.withLock { installed = false } }
}

private struct NullEmbedder: QueryEmbedding {
    func embedQuery(_ question: String) async throws -> [Float] { [] }
    func unload() async {}
}
