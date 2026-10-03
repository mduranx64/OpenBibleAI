//
//  BibleCatalogUpdatesTests.swift
//  OpenBibleAI
//

import BibleAI
import BibleDomain
import CryptoKit
import Foundation
import Testing
@testable import OpenBibleAI

/// The signed remote catalog: verification, merging with the built-in
/// catalog, and installed versions staying pinned to what they were
/// installed from.
@MainActor
struct BibleCatalogUpdatesTests {
    private static let key = Curve25519.Signing.PrivateKey()
    private static let repository = "owner/repo"

    private static func entry(_ id: String, revision: Int = 1, language: String = "en", repository: String = repository) throws -> BibleCatalogEntry {
        BibleCatalogEntry(
            version: try BibleVersion(id: id, name: id.uppercased(), abbreviation: id.uppercased(), languageCode: language, copyright: "Public domain"),
            manifest: ModelManifest(
                repository: repository,
                revision: "\(id)-\(revision)",
                files: [ModelManifest.File(name: "verses.json", size: 1_000, sha256: "")],
                host: .gitHubRelease(tag: "bibles")
            )
        )
    }

    private static func signed(_ document: BibleCatalogDocument, by key: Curve25519.Signing.PrivateKey = key) throws -> (catalog: Data, signature: Data) {
        let data = try JSONEncoder().encode(document)
        return (data, Data(try key.signature(for: data).base64EncodedString().utf8))
    }

    private static func document(sequence: Int, _ entries: [BibleCatalogEntry], schema: Int = 1) -> BibleCatalogDocument {
        BibleCatalogDocument(schema: schema, sequence: sequence, entries: entries)
    }

    private static let verifier = BibleCatalogVerifier(publicKey: key.publicKey, repository: repository, tag: "bibles")

    // MARK: - Verification

    @Test
    func aCatalogSignedWithTheAppsKeyIsAccepted() throws {
        let document = Self.document(sequence: 3, [try Self.entry("kjv"), try Self.entry("bsb")])
        let signed = try Self.signed(document)

        #expect(try Self.verifier.document(from: signed.catalog, signature: signed.signature) == document)
    }

    @Test
    func tamperedUnsignedOrForeignCatalogsAreRejected() throws {
        let document = Self.document(sequence: 3, [try Self.entry("kjv")])
        let signed = try Self.signed(document)

        var tampered = signed.catalog
        tampered[tampered.startIndex + 10] ^= 1
        #expect(throws: BibleCatalogVerifier.Rejection.badSignature) {
            try Self.verifier.document(from: tampered, signature: signed.signature)
        }
        let other = try Self.signed(document, by: Curve25519.Signing.PrivateKey())
        #expect(throws: BibleCatalogVerifier.Rejection.badSignature) {
            try Self.verifier.document(from: other.catalog, signature: other.signature)
        }
        let foreign = try Self.signed(Self.document(sequence: 3, [try Self.entry("kjv", repository: "attacker/repo")]))
        #expect(throws: BibleCatalogVerifier.Rejection.foreignHost("kjv")) {
            try Self.verifier.document(from: foreign.catalog, signature: foreign.signature)
        }
        let future = try Self.signed(Self.document(sequence: 3, [try Self.entry("kjv")], schema: 2))
        #expect(throws: BibleCatalogVerifier.Rejection.unsupportedSchema(2)) {
            try Self.verifier.document(from: future.catalog, signature: future.signature)
        }
    }

    @Test
    func thePublicKeyComesFromTheBuildSettingsAsHex() throws {
        let hex = Self.key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        let configured = BibleReleaseConfiguration(repository: "", tag: "bibles-test", publicKeyHex: hex)
        #expect(configured.catalogPublicKey?.rawRepresentation == Self.key.publicKey.rawRepresentation)
        #expect(configured.repository == "mduranx64/OpenBibleAI")
        #expect(configured.catalogURL.absoluteString == "https://github.com/mduranx64/OpenBibleAI/releases/download/bibles-test/catalog.json")

        // An unset build setting (empty) or a malformed key disables remote updates.
        #expect(BibleReleaseConfiguration(repository: "", tag: "", publicKeyHex: "").catalogPublicKey == nil)
        #expect(BibleReleaseConfiguration(repository: "", tag: "", publicKeyHex: "zz").catalogPublicKey == nil)
        // The generated file carries the xcconfig values.
        #expect(BibleReleaseConfiguration.main.tag == "bibles")
    }

    // MARK: - Merging

    @Test
    func theNewerCatalogLeadsAndInstalledVersionsKeepTheirEntry() throws {
        let builtIn = Self.document(sequence: 2, [try Self.entry("kjv"), try Self.entry("rv1909", language: "es")])
        let remote = Self.document(sequence: 5, [try Self.entry("kjv", revision: 2), try Self.entry("bsb")])
        let pinned = [try Self.entry("kjv")]

        let merged = BibleCatalogEntry.merged(builtIn: builtIn, remote: remote, pinned: pinned)

        #expect(merged.map(\.id) == ["kjv", "bsb", "rv1909"])
        #expect(merged[0].manifest.revision == "kjv-1", "The installed KJV stays on what it was installed from")
        #expect(BibleCatalogEntry.merged(builtIn: builtIn, remote: nil, pinned: []).map(\.id) == ["kjv", "rv1909"])
    }

    // MARK: - Library

    private struct Setup {
        let library: BibleLibraryModel
        let disk: FakeDisk
        let staged: FakeDisk
        let storage: InMemoryCatalogStorage
    }

    private func makeLibrary(
        builtIn: [BibleCatalogEntry],
        sequence: Int = 1,
        installed: [String: String] = [:],
        storage: InMemoryCatalogStorage = InMemoryCatalogStorage(),
        stagingStore: ((BibleCatalogEntry, FakeDisk) -> any LocalModelStoring)? = nil,
        fetch: @escaping @Sendable () async throws -> (catalog: Data, signature: Data)
    ) -> Setup {
        let disk = FakeDisk(installed: installed)
        let staged = FakeDisk(installed: [:])
        let makeStaged = stagingStore ?? { entry, staged in
            RevisionStore(id: entry.id, revision: entry.manifest.revision, disk: staged)
        }
        let library = BibleLibraryModel(
            catalog: builtIn,
            sequence: sequence,
            makeStore: { entry in RevisionStore(id: entry.id, revision: entry.manifest.revision, disk: disk) },
            updates: BibleCatalogUpdates(verifier: Self.verifier, storage: storage, fetch: fetch),
            staging: BibleUpdateStaging(
                makeStore: { entry in makeStaged(entry, staged) },
                promote: { id in
                    let revision = try #require(staged.revision(id))
                    disk.install(id, revision)
                    staged.remove(id)
                },
                discard: { id in staged.remove(id) }
            ),
            defaults: InMemoryDefaults(),
            load: { entry, _ in
                LoadedBible(
                    version: entry.version,
                    repositories: AppModel.Repositories(repository: InMemoryBibleRepository(verses: [])),
                    embeddingsURL: nil
                )
            }
        )
        return Setup(library: library, disk: disk, staged: staged, storage: storage)
    }

    @Test
    func aNewerRemoteCatalogOffersNewVersionsThatInstallAndStayPinned() async throws {
        let remote = try Self.signed(Self.document(sequence: 2, [try Self.entry("kjv"), try Self.entry("bsb")]))
        let setup = makeLibrary(builtIn: [try Self.entry("kjv")], installed: ["kjv": "kjv-1"]) { remote }
        await setup.library.refresh()
        #expect(setup.library.catalog.map(\.id) == ["kjv"])

        await setup.library.updateCatalog()

        #expect(setup.library.catalog.map(\.id) == ["kjv", "bsb"])
        await setup.library.install("bsb").value
        #expect(setup.library.installedIDs == ["kjv", "bsb"])
        #expect(await setup.storage.pinnedEntries().map(\.id) == ["bsb"])
    }

    @Test
    func olderOrInvalidRemoteCatalogsAreIgnored() async throws {
        let older = try Self.signed(Self.document(sequence: 1, [try Self.entry("bsb")]))
        let setup = makeLibrary(builtIn: [try Self.entry("kjv")], sequence: 4) { older }
        await setup.library.refresh()
        await setup.library.updateCatalog()
        #expect(setup.library.catalog.map(\.id) == ["kjv"])

        let forged = try Self.signed(Self.document(sequence: 9, [try Self.entry("bsb")]), by: Curve25519.Signing.PrivateKey())
        let attacked = makeLibrary(builtIn: [try Self.entry("kjv")]) { forged }
        await attacked.library.updateCatalog()
        #expect(attacked.library.catalog.map(\.id) == ["kjv"])
        #expect(await attacked.storage.cachedCatalog() == nil)
    }

    @Test
    func anInstalledVersionStaysInstalledWhenTheCatalogMovesToANewRevision() async throws {
        let storage = InMemoryCatalogStorage()
        await storage.pin(try Self.entry("bsb"))
        let remote = try Self.signed(Self.document(sequence: 2, [try Self.entry("bsb", revision: 2)]))
        let setup = makeLibrary(builtIn: [try Self.entry("kjv")], installed: ["bsb": "bsb-1"], storage: storage) { remote }

        await setup.library.updateCatalog()

        #expect(setup.library.installedIDs == ["bsb"])
        #expect(setup.library.entry("bsb")?.manifest.revision == "bsb-1")
    }

    @Test
    func theLastAcceptedCatalogIsUsedOffline() async throws {
        let storage = InMemoryCatalogStorage()
        let remote = try Self.signed(Self.document(sequence: 2, [try Self.entry("kjv"), try Self.entry("bsb")]))
        let online = makeLibrary(builtIn: [try Self.entry("kjv")], storage: storage) { remote }
        await online.library.updateCatalog()

        let offline = makeLibrary(builtIn: [try Self.entry("kjv")], storage: storage) { throw URLError(.notConnectedToInternet) }
        await offline.library.refresh()
        await offline.library.updateCatalog()

        #expect(offline.library.catalog.map(\.id) == ["kjv", "bsb"])
    }

    // MARK: - Updates

    /// BSB 1 installed and pinned, the remote catalog at BSB 2.
    private func installedBSBWithRemoteRevision2(
        stagingStore: ((BibleCatalogEntry, FakeDisk) -> any LocalModelStoring)? = nil
    ) async throws -> Setup {
        let storage = InMemoryCatalogStorage()
        await storage.pin(try Self.entry("bsb"))
        let remote = try Self.signed(Self.document(sequence: 2, [try Self.entry("kjv"), try Self.entry("bsb", revision: 2)]))
        let setup = makeLibrary(
            builtIn: [try Self.entry("kjv")],
            installed: ["bsb": "bsb-1"],
            storage: storage,
            stagingStore: stagingStore
        ) { remote }
        await setup.library.updateCatalog()
        return setup
    }

    @Test
    func aNewerRevisionIsOfferedWhileTheInstalledOneStaysReadable() async throws {
        let setup = try await installedBSBWithRemoteRevision2()

        #expect(setup.library.availableUpdate("bsb")?.manifest.revision == "bsb-2")
        #expect(setup.library.installedIDs == ["bsb"])
        #expect(try await setup.library.bible("bsb").version.id == "bsb")
        #expect(setup.library.availableUpdate("kjv") == nil, "Not installed")
    }

    @Test
    func updatingSwapsInTheNewRevisionPinsItAndReloadsIt() async throws {
        let setup = try await installedBSBWithRemoteRevision2()
        final class Reloads { var ids: [String] = [] }
        let reloads = Reloads()
        setup.library.versionUpdated = { reloads.ids.append($0) }

        await setup.library.update("bsb").value

        #expect(setup.disk.revision("bsb") == "bsb-2")
        #expect(setup.staged.revision("bsb") == nil)
        #expect(setup.library.installedIDs == ["bsb"])
        #expect(setup.library.activeVersionID == "bsb")
        #expect(setup.library.entry("bsb")?.manifest.revision == "bsb-2")
        #expect(await setup.storage.pinnedEntries().map(\.manifest.revision) == ["bsb-2"])
        #expect(setup.library.availableUpdate("bsb") == nil)
        #expect(setup.library.downloads["bsb"] == nil)
        #expect(reloads.ids == ["bsb"])
    }

    @Test
    func aFailedUpdateKeepsTheInstalledRevision() async throws {
        let setup = try await installedBSBWithRemoteRevision2 { _, _ in FailingStore() }

        await setup.library.update("bsb").value

        #expect(setup.disk.revision("bsb") == "bsb-1")
        #expect(setup.library.installedIDs == ["bsb"])
        #expect(setup.library.entry("bsb")?.manifest.revision == "bsb-1")
        #expect(await setup.storage.pinnedEntries().map(\.manifest.revision) == ["bsb-1"])
        #expect(setup.library.availableUpdate("bsb") != nil, "Still offered")
        guard case .failed = setup.library.downloads["bsb"] else {
            Issue.record("Expected a failure message")
            return
        }
    }

    @Test
    func aCancelledUpdateKeepsTheInstalledRevisionAndDiscardsTheDownload() async throws {
        let setup = try await installedBSBWithRemoteRevision2 { entry, staged in
            StallingStore(id: entry.id, revision: entry.manifest.revision, disk: staged)
        }

        let task = setup.library.update("bsb")
        try await waitUntil { setup.staged.revision("bsb") != nil }
        setup.library.cancel("bsb")
        await task.value

        #expect(setup.staged.revision("bsb") == nil)
        #expect(setup.disk.revision("bsb") == "bsb-1")
        #expect(setup.library.installedIDs == ["bsb"])
        #expect(setup.library.downloads["bsb"] == nil)
        #expect(setup.library.availableUpdate("bsb")?.manifest.revision == "bsb-2")
    }

    @Test
    func noUpdateIsOfferedForTheSameRevision() async throws {
        let storage = InMemoryCatalogStorage()
        await storage.pin(try Self.entry("bsb"))
        let remote = try Self.signed(Self.document(sequence: 2, [try Self.entry("bsb")]))
        let setup = makeLibrary(builtIn: [try Self.entry("kjv")], installed: ["bsb": "bsb-1"], storage: storage) { remote }
        await setup.library.updateCatalog()

        #expect(setup.library.availableUpdate("bsb") == nil)
        await setup.library.update("bsb").value
        #expect(setup.disk.revision("bsb") == "bsb-1")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

/// A download that always fails.
nonisolated struct FailingStore: LocalModelStoring {
    var directory: URL { URL(fileURLWithPath: "/tmp/fake-bibles/failing") }
    func isInstalled() async -> Bool { false }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws { throw URLError(.networkConnectionLost) }
    func delete() async throws {}
}

/// A download that writes its first file, then waits until cancelled.
nonisolated struct StallingStore: LocalModelStoring {
    let id: String
    let revision: String
    let disk: FakeDisk

    var directory: URL { URL(fileURLWithPath: "/tmp/fake-bibles/stalling") }
    func isInstalled() async -> Bool { false }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        disk.install(id, revision)
        try await Task.sleep(for: .seconds(60))
    }
    func delete() async throws {}
}

/// Which revision of each version is "on disk", shared by the stores.
nonisolated final class FakeDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: [String: String]

    init(installed: [String: String]) { self.installed = installed }

    func revision(_ id: String) -> String? { lock.withLock { installed[id] } }
    func install(_ id: String, _ revision: String) { lock.withLock { installed[id] = revision } }
    func remove(_ id: String) { lock.withLock { installed[id] = nil } }
}

/// Like `LocalModelStore`: installed only when the files on disk are the
/// store's revision.
nonisolated struct RevisionStore: LocalModelStoring {
    let id: String
    let revision: String
    let disk: FakeDisk

    var directory: URL { URL(fileURLWithPath: "/tmp/fake-bibles/\(id)") }
    func isInstalled() async -> Bool { disk.revision(id) == revision }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        disk.install(id, revision)
        progress(1)
    }
    func delete() async throws { disk.remove(id) }
}

nonisolated final class InMemoryCatalogStorage: BibleCatalogStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: [String: BibleCatalogEntry] = [:]
    private var cached: (catalog: Data, signature: Data)?

    func pinnedEntries() async -> [BibleCatalogEntry] { lock.withLock { pinned.values.sorted { $0.id < $1.id } } }
    func pin(_ entry: BibleCatalogEntry) async { lock.withLock { pinned[entry.id] = entry } }
    func unpin(_ id: String) async { lock.withLock { pinned[id] = nil } }
    func cachedCatalog() async -> (catalog: Data, signature: Data)? { lock.withLock { cached } }
    func cacheCatalog(_ catalog: Data, signature: Data) async { lock.withLock { cached = (catalog, signature) } }
}
