import BibleAI
import BibleDomain
import CryptoKit
import Foundation
import Testing
@testable import OpenBibleAI

/// The built-in catalog matches `Tools/BibleImport/catalog.json` (what gets
/// signed and published), and each entry describes exactly its package in
/// `Bibles/<id>` when that package is present locally (kjv and rv1909 are
/// versioned; the others are built with Tools/BibleImport).
struct PublishedBibleCatalogTests {
    private static let catalogURL = RepositoryBibles.root
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/BibleImport/catalog.json")

    nonisolated private static let verifyReleases =
        ProcessInfo.processInfo.environment["OPENBIBLE_VERIFY_RELEASES"] == "1"

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test
    func theBuiltInCatalogIsTheCommittedCatalogJSON() throws {
        let document = try JSONDecoder().decode(BibleCatalogDocument.self, from: Data(contentsOf: Self.catalogURL))
        #expect(document.schema == BibleCatalogDocument.currentSchema)
        #expect(document.sequence == BibleCatalogEntry.publishedSequence)
        #expect(document.entries == BibleCatalogEntry.published)
    }

    @Test(arguments: BibleCatalogEntry.published)
    func entryMatchesItsPackage(_ entry: BibleCatalogEntry) throws {
        #expect(entry.manifest.repository == "mduranx64/OpenBibleAI")
        #expect(entry.manifest.host == .gitHubRelease(tag: "bibles"))
        #expect(entry.manifest.revision.hasPrefix("\(entry.id)-"))
        #expect(entry.manifest.files.map(\.name).sorted() == ["books.json", "embeddings.bin", "verses.json", "version.json"])

        let package = RepositoryBibles.package(entry.id)
        guard FileManager.default.fileExists(atPath: package.appendingPathComponent("version.json").path) else { return }
        for file in entry.manifest.files {
            let data = try Data(contentsOf: package.appendingPathComponent(file.name))
            #expect(Int64(data.count) == file.size, "\(entry.id) \(file.name) size")
            #expect(Self.sha(data) == file.sha256, "\(entry.id) \(file.name) hash")
        }
        let version = try JSONDecoder().decode(
            BibleVersion.self,
            from: Data(contentsOf: package.appendingPathComponent("version.json"))
        )
        #expect(version == entry.version)
    }

    @Test
    func publishedIDsAreUnique() {
        let ids = BibleCatalogEntry.published.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Onboarding suggests the first entry of the reader's language.
    @Test
    func eachLanguageLeadsWithItsRecommendedVersion() {
        let first = { (language: String) in
            BibleCatalogEntry.published.first { $0.version.languageCode.hasPrefix(language) }?.id
        }
        #expect(first("en") == "kjv")
        #expect(first("es") == "rv1909")
        #expect(first("pt") == "blivre")
    }

    /// `TEST_RUNNER_OPENBIBLE_VERIFY_RELEASES=1`, after publishing: every
    /// pinned asset downloads from the release with its pinned size and hash.
    @Test(.enabled(if: PublishedBibleCatalogTests.verifyReleases))
    func everyPinnedAssetIsPublished() async throws {
        for entry in BibleCatalogEntry.published {
            for file in entry.manifest.files {
                let (data, response) = try await URLSession.shared.data(from: entry.manifest.url(for: file))
                #expect((response as? HTTPURLResponse)?.statusCode == 200, "\(entry.id) \(file.name)")
                let pinned = file.archive.map { ($0.size, $0.sha256) } ?? (file.size, file.sha256)
                #expect(Int64(data.count) == pinned.0, "\(entry.id) \(file.name) size")
                #expect(Self.sha(data) == pinned.1, "\(entry.id) \(file.name) hash")
            }
        }
    }
}
