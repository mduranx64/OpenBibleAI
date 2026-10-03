//
//  LocalModelStore.swift
//  BibleAI
//

import CryptoKit
import Foundation

/// Downloads a pinned model into an app-owned directory and verifies every
/// file's SHA-256 (and, for a file published compressed, the archive's
/// before decompressing it). The model counts as installed only after all files verify
/// (a completion marker is written last), so a partial download is never
/// used. Verified files are kept, so an interrupted download resumes.
public actor LocalModelStore: LocalModelStoring {
    public enum StoreError: Error, Equatable, Sendable {
        case checksumMismatch(String)
        case insufficientSpace(required: Int64, available: Int64)
    }

    public let manifest: ModelManifest
    public let directory: URL
    private let downloader: any ModelFileDownloading
    private let availableCapacity: @Sendable () -> Int64?

    private static let completionMarker = ".complete"
    private static let verifiedList = ".verified"

    public init(manifest: ModelManifest, directory: URL) {
        self.init(manifest: manifest, directory: directory, downloader: URLSessionModelFileDownloader())
    }

    init(
        manifest: ModelManifest,
        directory: URL,
        downloader: any ModelFileDownloading,
        availableCapacity: (@Sendable () -> Int64?)? = nil
    ) {
        self.manifest = manifest
        self.directory = directory
        self.downloader = downloader
        self.availableCapacity = availableCapacity ?? { Self.systemAvailableCapacity(near: directory) }
    }

    public func isInstalled() -> Bool {
        let marker = directory.appendingPathComponent(Self.completionMarker)
        guard let revision = try? String(contentsOf: marker, encoding: .utf8),
              revision == manifest.revision
        else { return false }
        return manifest.files.allSatisfy { hasExpectedSize($0) }
    }

    /// Downloads and verifies the missing files. `progress` receives 0…1.
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = directory
        try? excluded.setResourceValues(values)
        try? fileManager.removeItem(at: directory.appendingPathComponent(Self.completionMarker))

        var verified = loadVerified().filter { name in
            manifest.files.first { $0.name == name }.map(hasExpectedSize) ?? false
        }
        let remaining = manifest.files.filter { !verified.contains($0.name) }
        let required = remaining.reduce(0) { $0 + $1.size }
        if let available = availableCapacity(), available < required {
            throw StoreError.insufficientSpace(required: required, available: available)
        }

        let total = Double(max(manifest.downloadBytes, 1))
        var completed = manifest.files.filter { verified.contains($0.name) }.reduce(0) { $0 + $1.downloadSize }
        progress(Double(completed) / total)

        for file in remaining {
            try Task.checkCancellation()
            let base = completed
            let temporary = try await downloader.download(manifest.url(for: file)) { written in
                progress(Double(base + min(written, file.downloadSize)) / total)
            }
            let destination = directory.appendingPathComponent(file.name)
            try? fileManager.removeItem(at: destination)

            if let archive = file.archive {
                defer { try? fileManager.removeItem(at: temporary) }
                guard try await Self.sha256(of: temporary) == archive.sha256 else {
                    throw StoreError.checksumMismatch(file.name)
                }
                try await Self.inflate(temporary, to: destination)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }

            guard try await Self.sha256(of: destination) == file.sha256 else {
                try? fileManager.removeItem(at: destination)
                throw StoreError.checksumMismatch(file.name)
            }
            verified.insert(file.name)
            saveVerified(verified)
            completed += file.downloadSize
            progress(Double(completed) / total)
        }

        try manifest.revision.write(
            to: directory.appendingPathComponent(Self.completionMarker),
            atomically: true,
            encoding: .utf8
        )
        progress(1)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Helpers

    private func hasExpectedSize(_ file: ModelManifest.File) -> Bool {
        let url = directory.appendingPathComponent(file.name)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        return size == file.size
    }

    private func loadVerified() -> Set<String> {
        let url = directory.appendingPathComponent(Self.verifiedList)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").map(String.init)
        // First line is the revision; a different revision invalidates the list.
        guard lines.first == manifest.revision else { return [] }
        return Set(lines.dropFirst())
    }

    private func saveVerified(_ names: Set<String>) {
        let text = ([manifest.revision] + names.sorted()).joined(separator: "\n")
        try? text.write(to: directory.appendingPathComponent(Self.verifiedList), atomically: true, encoding: .utf8)
    }

    /// Hashes in 4 MB chunks off the caller's actor (model files are ~1 GB).
    @concurrent
    private static func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1_024 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Decompresses a raw-DEFLATE archive (published files are a few MB, so
    /// in memory), off the caller's actor.
    @concurrent
    private static func inflate(_ archive: URL, to destination: URL) async throws {
        let compressed = try Data(contentsOf: archive) as NSData
        try (compressed.decompressed(using: .zlib) as Data).write(to: destination)
    }

    private static func systemAvailableCapacity(near directory: URL) -> Int64? {
        var probe = directory
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// The store operations the app uses, so app tests can substitute a fake.
public protocol LocalModelStoring: Sendable {
    var directory: URL { get }
    func isInstalled() async -> Bool
    func download(progress: @escaping @Sendable (Double) -> Void) async throws
    func delete() async throws
}
