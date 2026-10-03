//
//  BibleLibraryModelTests.swift
//  OpenBibleAI
//

import BibleAI
import BibleDomain
import Foundation
import Testing
@testable import OpenBibleAI

@MainActor
struct BibleLibraryModelTests {
    private static func entry(_ id: String, language: String) throws -> BibleCatalogEntry {
        BibleCatalogEntry(
            version: try BibleVersion(id: id, name: id.uppercased(), abbreviation: id.uppercased(), languageCode: language, copyright: "Public domain"),
            manifest: ModelManifest(
                repository: "owner/repo",
                revision: "bible-\(id)-1",
                files: [ModelManifest.File(name: "verses.json", size: 1_000, sha256: "")],
                host: .gitHubRelease(tag: "bibles")
            )
        )
    }

    private struct Setup {
        let library: BibleLibraryModel
        let stores: [String: FakeBibleStore]
        let defaults: InMemoryDefaults
        let loads: LoadCounter
    }

    private func makeLibrary(
        installed: Set<String> = [],
        failing: Set<String> = [],
        blocking: Set<String> = [],
        defaults: InMemoryDefaults = InMemoryDefaults()
    ) throws -> Setup {
        let catalog = [try Self.entry("kjv", language: "en"), try Self.entry("rv1909", language: "es")]
        var stores: [String: FakeBibleStore] = [:]
        for entry in catalog {
            stores[entry.id] = FakeBibleStore(
                id: entry.id,
                installed: installed.contains(entry.id),
                failure: failing.contains(entry.id) ? URLError(.notConnectedToInternet) : nil,
                blocks: blocking.contains(entry.id)
            )
        }
        let loads = LoadCounter()
        let library = BibleLibraryModel(
            catalog: catalog,
            stores: stores,
            defaults: defaults,
            load: { entry, directory in
                loads.record(entry.id, directory)
                return LoadedBible(
                    version: entry.version,
                    repositories: AppModel.Repositories(repository: InMemoryBibleRepository(verses: [])),
                    embeddingsURL: nil
                )
            }
        )
        return Setup(library: library, stores: stores, defaults: defaults, loads: loads)
    }

    @Test
    func refreshFindsInstalledVersionsAndPicksTheFirstAsActive() async throws {
        let setup = try makeLibrary(installed: ["rv1909"])
        await setup.library.refresh()

        #expect(setup.library.installedVersions.map(\.id) == ["rv1909"])
        #expect(setup.library.activeVersionID == "rv1909")
        #expect(setup.library.needsOnboarding == false)
    }

    @Test
    func nothingInstalledNeedsOnboarding() async throws {
        let setup = try makeLibrary()
        await setup.library.refresh()

        #expect(setup.library.needsOnboarding)
        #expect(setup.library.activeVersionID == nil)
    }

    @Test
    func theSavedActiveVersionIsRestoredOnlyWhileInstalled() async throws {
        let defaults = InMemoryDefaults()
        let first = try makeLibrary(installed: ["kjv", "rv1909"], defaults: defaults)
        await first.library.refresh()
        first.library.activate("rv1909")

        let second = try makeLibrary(installed: ["kjv", "rv1909"], defaults: defaults)
        await second.library.refresh()
        #expect(second.library.activeVersionID == "rv1909")

        let third = try makeLibrary(installed: ["kjv"], defaults: defaults)
        await third.library.refresh()
        #expect(third.library.activeVersionID == "kjv")
    }

    @Test
    func installDownloadsReportsProgressAndActivatesTheFirstVersion() async throws {
        let setup = try makeLibrary()
        await setup.library.refresh()

        await setup.library.install("rv1909").value

        #expect(setup.stores["rv1909"]?.progressReported == true)
        #expect(setup.library.installedVersions.map(\.id) == ["rv1909"])
        #expect(setup.library.activeVersionID == "rv1909")
        #expect(setup.library.downloads["rv1909"] == nil)
    }

    @Test
    func installingASecondVersionKeepsTheActiveOne() async throws {
        let setup = try makeLibrary(installed: ["kjv"])
        await setup.library.refresh()

        await setup.library.install("rv1909").value

        #expect(setup.library.installedVersions.map(\.id) == ["kjv", "rv1909"])
        #expect(setup.library.activeVersionID == "kjv")
    }

    @Test
    func aFailedDownloadShowsAMessageAndCanBeRetried() async throws {
        let setup = try makeLibrary(failing: ["kjv"])
        await setup.library.refresh()

        await setup.library.install("kjv").value

        guard case .failed = setup.library.downloads["kjv"] else {
            Issue.record("Expected a failure, got \(String(describing: setup.library.downloads["kjv"]))")
            return
        }
        #expect(setup.library.installedVersions.isEmpty)
    }

    @Test
    func cancellingStopsTheDownloadWithoutInstalling() async throws {
        let setup = try makeLibrary(blocking: ["kjv"])
        await setup.library.refresh()

        let task = setup.library.install("kjv")
        #expect(setup.library.downloads["kjv"] == .downloading(0))
        setup.library.cancel("kjv")
        await task.value

        #expect(setup.library.downloads["kjv"] == nil)
        #expect(setup.library.installedVersions.isEmpty)
    }

    @Test
    func deleteRefusesTheActiveAndTheLastVersion() async throws {
        let setup = try makeLibrary(installed: ["kjv", "rv1909"])
        await setup.library.refresh()
        #expect(setup.library.activeVersionID == "kjv")

        #expect(await setup.library.delete("kjv") == false)
        #expect(setup.stores["kjv"]?.deleted == false)

        #expect(await setup.library.delete("rv1909"))
        #expect(setup.stores["rv1909"]?.deleted == true)
        #expect(setup.library.installedVersions.map(\.id) == ["kjv"])
    }

    @Test
    func loadedBiblesAreCachedUntilDeleted() async throws {
        let setup = try makeLibrary(installed: ["kjv", "rv1909"])
        await setup.library.refresh()

        let first = try await setup.library.bible("rv1909")
        _ = try await setup.library.bible("rv1909")
        #expect(first.version.id == "rv1909")
        #expect(setup.loads.ids == ["rv1909"])
        #expect(setup.loads.directories.first?.lastPathComponent == "rv1909")

        _ = await setup.library.delete("rv1909")
        await #expect(throws: BibleLibraryModel.LibraryError.notInstalled("rv1909")) {
            try await setup.library.bible("rv1909")
        }
    }

    @Test(arguments: [
        (["es-CL", "en-US"], "rv1909"),
        (["pt-BR"], "kjv"),
        (["fr-FR"], "kjv"),
        (["en-GB", "es-ES"], "kjv"),
    ])
    func suggestionFollowsThePreferredLanguages(languages: [String], expected: String) throws {
        let setup = try makeLibrary()
        #expect(setup.library.suggestedVersionID(preferredLanguages: languages) == expected)
    }
}

/// Records which versions were loaded and from where.
nonisolated final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _ids: [String] = []
    private var _directories: [URL] = []

    var ids: [String] { lock.withLock { _ids } }
    var directories: [URL] { lock.withLock { _directories } }

    func record(_ id: String, _ directory: URL) {
        lock.withLock {
            _ids.append(id)
            _directories.append(directory)
        }
    }
}

nonisolated final class FakeBibleStore: LocalModelStoring, @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private var installed: Bool
    private let failure: (any Error)?
    private let blocks: Bool
    private var _progressReported = false
    private var _deleted = false

    init(id: String, installed: Bool, failure: (any Error)? = nil, blocks: Bool = false) {
        self.directory = URL(fileURLWithPath: "/tmp/fake-bibles/\(id)")
        self.installed = installed
        self.failure = failure
        self.blocks = blocks
    }

    var progressReported: Bool { lock.withLock { _progressReported } }
    var deleted: Bool { lock.withLock { _deleted } }

    func isInstalled() async -> Bool { lock.withLock { installed } }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        lock.withLock { _progressReported = true }
        if blocks { try await Task.sleep(for: .seconds(60)) }
        if let failure { throw failure }
        progress(1)
        lock.withLock { installed = true }
    }

    func delete() async throws {
        lock.withLock {
            installed = false
            _deleted = true
        }
    }
}

nonisolated final class InMemoryDefaults: ReadingPositionStorage, @unchecked Sendable {
    private var storage: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}
