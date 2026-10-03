//
//  BibleCatalogUpdates.swift
//  OpenBibleAI
//

import BibleAI
import CryptoKit
import Foundation

/// The list of downloadable versions as published (`catalog.json` in the
/// shared release, and `Tools/BibleImport/catalog.json` for the built-in copy).
/// `sequence` grows with every publication, so an older catalog never
/// replaces a newer one.
nonisolated struct BibleCatalogDocument: Codable, Equatable, Sendable {
    static let currentSchema = 1

    let schema: Int
    let sequence: Int
    let entries: [BibleCatalogEntry]
}

/// Where Bible versions are published, from the build settings
/// `BIBLE_RELEASE_REPOSITORY`, `BIBLE_RELEASE_TAG` and
/// `BIBLE_CATALOG_PUBLIC_KEY` (hex; set in `Config/Local.xcconfig`), which
/// `Tools/generate_build_settings.sh` writes into the generated
/// `BuildSettings`. Without a public key the app uses only its built-in catalog.
nonisolated struct BibleReleaseConfiguration: Sendable {
    let repository: String
    let tag: String
    let catalogPublicKey: Curve25519.Signing.PublicKey?

    static let main = BibleReleaseConfiguration(
        repository: BuildSettings.bibleReleaseRepository,
        tag: BuildSettings.bibleReleaseTag,
        publicKeyHex: BuildSettings.bibleCatalogPublicKey
    )

    init(repository: String, tag: String, catalogPublicKey: Curve25519.Signing.PublicKey?) {
        self.repository = repository
        self.tag = tag
        self.catalogPublicKey = catalogPublicKey
    }

    /// Empty values fall back to this repository's `bibles` release; an empty
    /// or malformed key turns remote catalogs off.
    init(repository: String, tag: String, publicKeyHex: String) {
        self.init(
            repository: repository.isEmpty ? "mduranx64/OpenBibleAI" : repository,
            tag: tag.isEmpty ? "bibles" : tag,
            catalogPublicKey: Self.bytes(hex: publicKeyHex)
                .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        )
    }

    /// The key is hex in the build settings (base64 can contain "//", which
    /// starts a comment in an xcconfig file).
    static func bytes(hex: String) -> Data? {
        let digits = Array(hex.trimmingCharacters(in: .whitespaces))
        guard digits.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            data.append(byte)
        }
        return data
    }

    var catalogURL: URL {
        URL(string: "https://github.com/\(repository)/releases/download/\(tag)/catalog.json")!
    }

    var signatureURL: URL {
        catalogURL.appendingPathExtension("sig")
    }
}

/// Accepts a downloaded catalog only if its Ed25519 signature verifies with
/// the app's public key and every entry downloads from this app's release
/// (so even a leaked signing key can't point the app at another host).
nonisolated struct BibleCatalogVerifier: Sendable {
    enum Rejection: Error, Equatable {
        case badSignature
        case unreadable
        case unsupportedSchema(Int)
        case duplicateID(String)
        case foreignHost(String)
    }

    let publicKey: Curve25519.Signing.PublicKey
    let repository: String
    let tag: String

    /// `signature` is the `.sig` asset: the signature's 64 bytes in base64.
    func document(from data: Data, signature: Data) throws(Rejection) -> BibleCatalogDocument {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bytes = Data(base64Encoded: text), publicKey.isValidSignature(bytes, for: data) else {
            throw .badSignature
        }
        guard let document = try? JSONDecoder().decode(BibleCatalogDocument.self, from: data) else {
            throw .unreadable
        }
        guard document.schema == BibleCatalogDocument.currentSchema else {
            throw .unsupportedSchema(document.schema)
        }
        var seen: Set<String> = []
        for entry in document.entries {
            guard seen.insert(entry.id).inserted else { throw .duplicateID(entry.id) }
            guard entry.manifest.repository == repository, entry.manifest.host == .gitHubRelease(tag: tag) else {
                throw .foreignHost(entry.id)
            }
        }
        return document
    }
}

/// What the library remembers between launches: the entry each installed
/// version was installed from (so it stays readable whatever the catalog
/// later says) and the last accepted signed catalog.
nonisolated protocol BibleCatalogStorage: Sendable {
    func pinnedEntries() async -> [BibleCatalogEntry]
    func pin(_ entry: BibleCatalogEntry) async
    func unpin(_ id: String) async
    func cachedCatalog() async -> (catalog: Data, signature: Data)?
    func cacheCatalog(_ catalog: Data, signature: Data) async
}

/// Remote catalog updates for the library: where to fetch, how to verify and
/// where to remember.
nonisolated struct BibleCatalogUpdates: Sendable {
    let verifier: BibleCatalogVerifier
    let storage: any BibleCatalogStorage
    let fetch: @Sendable () async throws -> (catalog: Data, signature: Data)

    /// Signed updates from the configured release, or nil without a public key.
    static func live(
        configuration: BibleReleaseConfiguration = .main,
        directory: URL
    ) -> BibleCatalogUpdates? {
        guard let key = configuration.catalogPublicKey else { return nil }
        return BibleCatalogUpdates(
            verifier: BibleCatalogVerifier(publicKey: key, repository: configuration.repository, tag: configuration.tag),
            storage: FileBibleCatalogStorage(directory: directory),
            fetch: {
                let settings = URLSessionConfiguration.ephemeral
                settings.timeoutIntervalForRequest = 15
                let session = URLSession(configuration: settings)
                async let catalog = session.data(from: configuration.catalogURL)
                async let signature = session.data(from: configuration.signatureURL)
                let (catalogData, catalogResponse) = try await catalog
                let (signatureData, signatureResponse) = try await signature
                for response in [catalogResponse, signatureResponse] {
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                }
                return (catalogData, signatureData)
            }
        )
    }
}

/// Catalog state as files in the Bibles directory: `<id>/entry.json` for each
/// installed version (removed with the version's folder) and
/// `catalog.json` + `catalog.json.sig`.
nonisolated struct FileBibleCatalogStorage: BibleCatalogStorage {
    let directory: URL

    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    private var signatureURL: URL { directory.appendingPathComponent("catalog.json.sig") }

    private func entryURL(_ id: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("entry.json")
    }

    func pinnedEntries() async -> [BibleCatalogEntry] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            (try? Data(contentsOf: folder.appendingPathComponent("entry.json")))
                .flatMap { try? JSONDecoder().decode(BibleCatalogEntry.self, from: $0) }
        }
        .sorted { $0.id < $1.id }
    }

    func pin(_ entry: BibleCatalogEntry) async {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: entryURL(entry.id), options: .atomic)
    }

    func unpin(_ id: String) async {
        try? FileManager.default.removeItem(at: entryURL(id))
    }

    func cachedCatalog() async -> (catalog: Data, signature: Data)? {
        guard let catalog = try? Data(contentsOf: catalogURL),
              let signature = try? Data(contentsOf: signatureURL)
        else { return nil }
        return (catalog, signature)
    }

    func cacheCatalog(_ catalog: Data, signature: Data) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? catalog.write(to: catalogURL, options: .atomic)
        try? signature.write(to: signatureURL, options: .atomic)
    }
}

extension BibleCatalogEntry {
    /// The versions to offer: the newer of the built-in and remote catalogs
    /// (by sequence) in its order, then any versions only the other one has,
    /// with each installed version replaced by the entry it was installed from.
    nonisolated static func merged(
        builtIn: BibleCatalogDocument,
        remote: BibleCatalogDocument?,
        pinned: [BibleCatalogEntry]
    ) -> [BibleCatalogEntry] {
        let documents = [builtIn, remote].compactMap(\.self).sorted { $0.sequence > $1.sequence }
        var merged: [BibleCatalogEntry] = []
        for entry in documents.flatMap(\.entries) where !merged.contains(where: { $0.id == entry.id }) {
            merged.append(entry)
        }
        for entry in pinned {
            if let index = merged.firstIndex(where: { $0.id == entry.id }) {
                merged[index] = entry
            } else {
                merged.append(entry)
            }
        }
        return merged
    }
}
