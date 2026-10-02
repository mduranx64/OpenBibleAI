//
//  LocalModelStoreTests.swift
//  BibleAI
//

import CryptoKit
import Foundation
import Testing

@testable import BibleAI

struct LocalModelStoreTests {
    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private let files: [String: Data] = [
        "config.json": Data("{\"model\":1}".utf8),
        "model.safetensors": Data(repeating: 7, count: 4_096)
    ]

    private func manifest(corrupt: String? = nil) -> ModelManifest {
        ModelManifest(
            repository: "test/model",
            revision: "abc123",
            files: files.keys.sorted().map { name in
                ModelManifest.File(
                    name: name,
                    size: Int64(files[name]!.count),
                    sha256: name == corrupt ? String(repeating: "0", count: 64) : Self.sha(files[name]!)
                )
            }
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelStoreTests-\(UUID().uuidString)")
    }

    @Test
    func downloadVerifiesEveryFileAndMarksTheModelInstalled() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = FakeModelDownloader(files: files)
        let store = LocalModelStore(manifest: manifest(), directory: directory, downloader: downloader)

        #expect(await store.isInstalled() == false)
        let progress = ProgressRecorder()
        try await store.download { progress.record($0) }

        #expect(await store.isInstalled())
        #expect(downloader.requested.map(\.lastPathComponent).sorted() == files.keys.sorted())
        #expect(downloader.requested.allSatisfy { $0.absoluteString.contains("/test/model/resolve/abc123/") })
        #expect(progress.values.last == 1)
        #expect(progress.values == progress.values.sorted(), "Progress never goes backwards")
        let config = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        #expect(config == files["config.json"])
    }

    @Test
    func checksumMismatchRemovesTheFileAndLeavesTheModelNotInstalled() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalModelStore(
            manifest: manifest(corrupt: "model.safetensors"),
            directory: directory,
            downloader: FakeModelDownloader(files: files)
        )

        await #expect(throws: LocalModelStore.StoreError.checksumMismatch("model.safetensors")) {
            try await store.download { _ in }
        }
        #expect(await store.isInstalled() == false)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors").path))
    }

    @Test
    func interruptedDownloadIsNotInstalledAndResumesWithoutRefetchingVerifiedFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = FakeModelDownloader(files: files, failOn: "model.safetensors")
        let first = LocalModelStore(manifest: manifest(), directory: directory, downloader: failing)

        await #expect(throws: FakeModelDownloader.Failure.self) {
            try await first.download { _ in }
        }
        #expect(await first.isInstalled() == false)

        let working = FakeModelDownloader(files: files)
        let second = LocalModelStore(manifest: manifest(), directory: directory, downloader: working)
        try await second.download { _ in }

        #expect(await second.isInstalled())
        #expect(working.requested.map(\.lastPathComponent) == ["model.safetensors"])
    }

    @Test
    func insufficientSpaceFailsBeforeDownloading() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = FakeModelDownloader(files: files)
        let store = LocalModelStore(
            manifest: manifest(),
            directory: directory,
            downloader: downloader,
            availableCapacity: { 10 }
        )

        await #expect(throws: LocalModelStore.StoreError.insufficientSpace(required: manifest().totalBytes, available: 10)) {
            try await store.download { _ in }
        }
        #expect(downloader.requested.isEmpty)
    }

    @Test
    func deleteRemovesAnInstalledModel() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalModelStore(manifest: manifest(), directory: directory, downloader: FakeModelDownloader(files: files))
        try await store.download { _ in }

        try await store.delete()

        #expect(await store.isInstalled() == false)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func pinnedManifestsAreComplete() {
        for manifest in [ModelManifest.qwen3_1_7B, ModelManifest.qwen3_0_6B, ModelManifest.qwen3Embedding] {
            #expect(manifest.revision.count == 40)
            #expect(manifest.files.contains { $0.name == "model.safetensors" })
            #expect(manifest.files.contains { $0.name == "tokenizer.json" })
            #expect(manifest.files.contains { $0.name == "config.json" })
            #expect(manifest.files.allSatisfy { $0.sha256.count == 64 && $0.size > 0 })
        }
        #expect(MLXModelTier.standard.manifest == .qwen3_1_7B)
        #expect(MLXModelTier.compact.manifest == .qwen3_0_6B)
    }
}

/// Writes canned data to a temporary file, optionally failing for one file.
private final class FakeModelDownloader: ModelFileDownloading, @unchecked Sendable {
    struct Failure: Error {}

    private let files: [String: Data]
    private let failOn: String?
    private let lock = NSLock()
    private var stored: [URL] = []

    init(files: [String: Data], failOn: String? = nil) {
        self.files = files
        self.failOn = failOn
    }

    var requested: [URL] { lock.withLock { stored } }

    func download(
        _ url: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        lock.withLock { stored.append(url) }
        let name = url.lastPathComponent
        if name == failOn { throw Failure() }
        let data = files[name] ?? Data()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: temporary)
        progress(Int64(data.count))
        return temporary
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    var values: [Double] { lock.withLock { stored } }
    func record(_ value: Double) { lock.withLock { stored.append(value) } }
}
