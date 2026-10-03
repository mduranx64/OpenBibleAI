//
//  BibleLibraryModel.swift
//  OpenBibleAI
//

import BibleAI
import BibleData
import BibleDomain
import Foundation
import Observation

/// A Bible version offered for download, pinned to its release files.
nonisolated struct BibleCatalogEntry: Identifiable, Equatable, Sendable, Codable {
    let version: BibleVersion
    let manifest: ModelManifest

    var id: String { version.id }
    /// Bytes to download (files are published compressed where it helps).
    var downloadSize: Int64 { manifest.downloadBytes }
}

/// Where a newer revision of an installed version downloads (beside it, so
/// the installed one stays readable) and how it then replaces it.
nonisolated struct BibleUpdateStaging: Sendable {
    let makeStore: @Sendable (BibleCatalogEntry) -> any LocalModelStoring
    /// Moves the staged version (by ID) over the installed one.
    let promote: @Sendable (String) async throws -> Void
    /// Removes a staged download that failed or was cancelled.
    let discard: @Sendable (String) async -> Void

    /// Staging in `<directory>/.staging/<id>`, swapped in with one replace.
    static func live(directory: URL) -> BibleUpdateStaging {
        let staging = directory.appendingPathComponent(".staging", isDirectory: true)
        return BibleUpdateStaging(
            makeStore: { entry in
                LocalModelStore(manifest: entry.manifest, directory: staging.appendingPathComponent(entry.id, isDirectory: true))
            },
            promote: { id in
                _ = try FileManager.default.replaceItemAt(
                    directory.appendingPathComponent(id, isDirectory: true),
                    withItemAt: staging.appendingPathComponent(id, isDirectory: true)
                )
            },
            discard: { id in
                try? FileManager.default.removeItem(at: staging.appendingPathComponent(id, isDirectory: true))
            }
        )
    }
}

/// An installed version, loaded for reading, search and the chat.
nonisolated struct LoadedBible: Sendable {
    let version: BibleVersion
    let repositories: AppModel.Repositories
    /// The version's verse-embedding index for semantic search, if any.
    let embeddingsURL: URL?
}

/// The Bible versions the user can install: download (verified, resumable),
/// delete, the active reading version, and loading installed versions.
/// The catalog starts as the built-in one and, with `updates`, takes newer
/// versions from the signed remote catalog; installed versions stay pinned to
/// the entry they were installed from until the user updates them.
/// UI-facing, main-actor state.
@MainActor
@Observable
final class BibleLibraryModel {
    enum DownloadState: Equatable {
        case downloading(Double)
        case failed(String)
    }

    enum LibraryError: Error, Equatable {
        case notInstalled(String)
    }

    private(set) var catalog: [BibleCatalogEntry]
    /// The newest entry of each version, ignoring what is installed.
    private(set) var latest: [String: BibleCatalogEntry]
    private(set) var installedIDs: Set<String> = []
    /// Downloads in progress or failed, by version ID.
    private(set) var downloads: [String: DownloadState] = [:]
    private(set) var activeVersionID: String?
    private(set) var hasRefreshed = false

    @ObservationIgnored private var stores: [String: any LocalModelStoring]
    /// The manifest each store was made for, to replace a store whose entry changed.
    @ObservationIgnored private var storeManifests: [String: ModelManifest] = [:]
    @ObservationIgnored private let builtIn: BibleCatalogDocument
    @ObservationIgnored private var remote: BibleCatalogDocument?
    @ObservationIgnored private let makeStore: ((BibleCatalogEntry) -> any LocalModelStoring)?
    @ObservationIgnored private let updates: BibleCatalogUpdates?
    @ObservationIgnored private let staging: BibleUpdateStaging?
    @ObservationIgnored private let defaults: any ReadingPositionStorage
    @ObservationIgnored private let load: @Sendable (BibleCatalogEntry, URL) async throws -> LoadedBible
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private var loaded: [String: Task<LoadedBible, any Error>] = [:]
    /// Called after a version was updated, to reload it if it is being read.
    @ObservationIgnored var versionUpdated: (@MainActor (String) async -> Void)?

    private static let activeVersionKey = "bible.activeVersion"

    /// `stores` serve the given catalog; `makeStore` makes stores for entries
    /// that arrive later (remote or pinned) or change.
    init(
        catalog: [BibleCatalogEntry],
        sequence: Int = 0,
        stores: [String: any LocalModelStoring] = [:],
        makeStore: ((BibleCatalogEntry) -> any LocalModelStoring)? = nil,
        updates: BibleCatalogUpdates? = nil,
        staging: BibleUpdateStaging? = nil,
        defaults: any ReadingPositionStorage,
        load: @escaping @Sendable (BibleCatalogEntry, URL) async throws -> LoadedBible = BibleLibraryModel.loadPackage
    ) {
        self.catalog = catalog
        self.latest = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.builtIn = BibleCatalogDocument(schema: BibleCatalogDocument.currentSchema, sequence: sequence, entries: catalog)
        self.stores = stores
        self.makeStore = makeStore
        self.updates = updates
        self.staging = staging
        self.defaults = defaults
        self.load = load
        for entry in catalog where stores[entry.id] != nil {
            storeManifests[entry.id] = entry.manifest
        }
        syncStores()
    }

    /// The app's library: the built-in catalog plus signed remote updates
    /// (when a catalog key is configured), stored under Application Support.
    static func live(defaults: any ReadingPositionStorage = UserDefaults.standard) -> BibleLibraryModel {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("OpenBibleAI", isDirectory: true)
            .appendingPathComponent("Bibles", isDirectory: true)
        return BibleLibraryModel(
            catalog: BibleCatalogEntry.published,
            sequence: BibleCatalogEntry.publishedSequence,
            makeStore: { entry in
                LocalModelStore(manifest: entry.manifest, directory: directory.appendingPathComponent(entry.id, isDirectory: true))
            },
            updates: BibleCatalogUpdates.live(directory: directory),
            staging: .live(directory: directory),
            defaults: defaults
        )
    }

    @concurrent
    nonisolated static func loadPackage(_ entry: BibleCatalogEntry, from directory: URL) async throws -> LoadedBible {
        let package = try await BibleVersionPackage.load(from: directory)
        let repository = CachingBibleRepository(base: package.repository)
        return LoadedBible(
            version: package.version,
            repositories: AppModel.Repositories(
                verses: repository,
                catalog: package.repository,
                text: package.repository,
                passages: package.repository
            ),
            embeddingsURL: package.embeddingsURL
        )
    }

    // MARK: - State

    var installedVersions: [BibleVersion] {
        catalog.filter { installedIDs.contains($0.id) }.map(\.version)
    }

    var activeVersion: BibleVersion? {
        catalog.first { $0.id == activeVersionID }?.version
    }

    /// No version is installed yet: the user must pick one to download.
    var needsOnboarding: Bool {
        hasRefreshed && installedIDs.isEmpty
    }

    func entry(_ id: String) -> BibleCatalogEntry? {
        catalog.first { $0.id == id }
    }

    /// The newer revision of an installed version, if the catalog moved on.
    func availableUpdate(_ id: String) -> BibleCatalogEntry? {
        guard installedIDs.contains(id),
              let installed = entry(id),
              let newest = latest[id],
              newest.manifest.revision != installed.manifest.revision
        else { return nil }
        return newest
    }

    func refresh() async {
        if let updates {
            if remote == nil, let cached = await updates.storage.cachedCatalog() {
                remote = try? updates.verifier.document(from: cached.catalog, signature: cached.signature)
            }
            catalog = BibleCatalogEntry.merged(builtIn: builtIn, remote: remote, pinned: await updates.storage.pinnedEntries())
            let newest = BibleCatalogEntry.merged(builtIn: builtIn, remote: remote, pinned: [])
            latest = Dictionary(newest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            syncStores()
        }

        var installed: Set<String> = []
        for entry in catalog where await stores[entry.id]?.isInstalled() == true {
            installed.insert(entry.id)
        }
        installedIDs = installed

        let saved = defaults.data(forKey: Self.activeVersionKey).flatMap { String(data: $0, encoding: .utf8) }
        if let saved, installed.contains(saved) {
            activeVersionID = saved
        } else {
            activeVersionID = catalog.first { installed.contains($0.id) }?.id
        }
        hasRefreshed = true
    }

    /// Fetches the signed remote catalog and, if it verifies and is at least
    /// as new as the one in use, remembers it and offers its versions.
    /// Failures (offline, bad signature, older catalog) keep the current one.
    func updateCatalog() async {
        guard let updates,
              let fetched = try? await updates.fetch(),
              let document = try? updates.verifier.document(from: fetched.catalog, signature: fetched.signature),
              document.sequence >= max(remote?.sequence ?? 0, builtIn.sequence)
        else { return }
        await updates.storage.cacheCatalog(fetched.catalog, signature: fetched.signature)
        remote = document
        await refresh()
    }

    /// Makes an installed version the reading version and remembers it.
    func activate(_ id: String) {
        guard installedIDs.contains(id) else { return }
        activeVersionID = id
        defaults.set(Data(id.utf8), forKey: Self.activeVersionKey)
    }

    // MARK: - Download

    @discardableResult
    func install(_ id: String) -> Task<Void, Never> {
        if let task = tasks[id] { return task }
        guard let store = stores[id] else { return Task {} }
        // The entry the store downloads, remembered once it's installed.
        let installing = entry(id)
        return download(id, with: store) { library in
            if let installing { await library.updates?.storage.pin(installing) }
        }
    }

    /// Downloads the newer revision beside the installed one, then swaps it
    /// in and reloads it; until then the installed revision stays readable.
    /// A failed or cancelled update keeps the installed revision.
    @discardableResult
    func update(_ id: String) -> Task<Void, Never> {
        if let task = tasks[id] { return task }
        guard let newest = availableUpdate(id), let staging else { return Task {} }
        return download(id, with: staging.makeStore(newest), abandon: { await staging.discard(id) }) { library in
            try await staging.promote(id)
            library.loaded[id]?.cancel()
            library.loaded[id] = nil
            await library.updates?.storage.pin(newest)
        } reload: { library in
            await library.versionUpdated?(id)
        }
    }

    /// Runs one download with progress, cancellation and failure reporting.
    /// `finish` completes a successful download (an error fails it), then the
    /// library refreshes and `reload` runs; `abandon` cleans up otherwise.
    private func download(
        _ id: String,
        with store: any LocalModelStoring,
        abandon: @escaping @MainActor () async -> Void = {},
        finish: @escaping @MainActor (BibleLibraryModel) async throws -> Void,
        reload: @escaping @MainActor (BibleLibraryModel) async -> Void = { _ in }
    ) -> Task<Void, Never> {
        let generation = (generations[id] ?? 0) + 1
        generations[id] = generation
        downloads[id] = .downloading(0)

        // Called off the main actor by the store; hops back to report.
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                self?.reportProgress(fraction, id: id, generation: generation)
            }
        }

        let task = Task { [weak self] in
            var outcome: DownloadState?
            var succeeded = false
            do {
                try await store.download(progress: report)
                succeeded = true
            } catch is CancellationError {
                outcome = nil
            } catch {
                outcome = .failed(Self.message(for: error))
            }
            // Cancelled or replaced by a newer download.
            guard let self, generation == self.generations[id] else {
                await abandon()
                return
            }
            if succeeded {
                do {
                    try await finish(self)
                } catch {
                    succeeded = false
                    outcome = .failed(Self.message(for: error))
                }
            }
            if !succeeded { await abandon() }
            self.downloads[id] = outcome
            self.tasks[id] = nil
            let hadActive = self.activeVersionID != nil
            await self.refresh()
            if !hadActive, self.installedIDs.contains(id) {
                self.activate(id)
            }
            if succeeded { await reload(self) }
        }
        tasks[id] = task
        return task
    }

    func cancel(_ id: String) {
        generations[id, default: 0] += 1
        tasks[id]?.cancel()
        tasks[id] = nil
        downloads[id] = nil
    }

    /// Deletes an installed version. The active version and the last one
    /// can't be deleted (the reader always needs a Bible); returns false then.
    func delete(_ id: String) async -> Bool {
        guard id != activeVersionID, installedIDs.subtracting([id]).count >= 1 else { return false }
        cancel(id)
        loaded[id]?.cancel()
        loaded[id] = nil
        try? await stores[id]?.delete()
        await updates?.storage.unpin(id)
        await refresh()
        return true
    }

    // MARK: - Loading

    /// The installed version, loaded once and then reused.
    func bible(_ id: String) async throws -> LoadedBible {
        guard installedIDs.contains(id), let entry = entry(id), let store = stores[id] else {
            throw LibraryError.notInstalled(id)
        }
        if let task = loaded[id] { return try await task.value }

        let load = self.load
        let directory = store.directory
        let task = Task { try await load(entry, directory) }
        loaded[id] = task
        do {
            return try await task.value
        } catch {
            if loaded[id] == task { loaded[id] = nil }
            throw error
        }
    }

    /// The first catalog version in one of the user's preferred languages,
    /// otherwise the first version (the KJV).
    func suggestedVersionID(preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
        for language in preferredLanguages {
            let base = Locale.Language(identifier: language).languageCode?.identifier
            if let match = catalog.first(where: {
                Locale.Language(identifier: $0.version.languageCode).languageCode?.identifier == base
            }) {
                return match.id
            }
        }
        return catalog.first?.id
    }

    // MARK: - Helpers

    /// Makes a store for each catalog entry without one, or whose entry
    /// changed (never while it downloads).
    private func syncStores() {
        guard let makeStore else { return }
        for entry in catalog where storeManifests[entry.id] != entry.manifest && tasks[entry.id] == nil {
            stores[entry.id] = makeStore(entry)
            storeManifests[entry.id] = entry.manifest
        }
    }

    /// Late progress callbacks from an older or finished download are ignored.
    private func reportProgress(_ fraction: Double, id: String, generation: Int) {
        guard generation == generations[id],
              case let .downloading(current) = downloads[id],
              fraction >= current
        else { return }
        downloads[id] = .downloading(fraction)
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case let LocalModelStore.StoreError.insufficientSpace(required, available):
            let formatter = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return String(localized: "Not enough free space: this Bible needs \(formatter(required)), \(formatter(available)) available.")
        case LocalModelStore.StoreError.checksumMismatch:
            return String(localized: "The download was damaged. Please try again.")
        default:
            return String(localized: "The download failed: \(error.localizedDescription)")
        }
    }
}

extension AppModel.Repositories {
    /// All four roles served by one repository (tests and fixtures).
    nonisolated init<Repository>(repository: Repository)
    where Repository: BibleRepository & BibleCatalogRepository & BibleTextSearchRepository & BiblePassageSearchRepository {
        self.init(verses: repository, catalog: repository, text: repository, passages: repository)
    }
}
