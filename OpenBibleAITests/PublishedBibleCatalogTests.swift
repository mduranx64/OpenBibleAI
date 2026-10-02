import BibleAI
import BibleDomain
import CryptoKit
import Foundation
import Testing
@testable import OpenBibleAI

/// The pinned KJV entry describes exactly the package in `Bibles/kjv`, which
/// is what gets uploaded to its release.
struct PublishedBibleCatalogTests {
    @Test
    func theKJVEntryMatchesTheRepositoryPackage() throws {
        let entry = try #require(BibleCatalogEntry.published.first { $0.id == "kjv" })
        #expect(entry.manifest.host == .gitHubRelease)
        #expect(entry.manifest.files.map(\.name).sorted() == ["books.json", "embeddings.bin", "verses.json", "version.json"])

        for file in entry.manifest.files {
            let data = try Data(contentsOf: RepositoryBibles.kjv.appendingPathComponent(file.name))
            #expect(Int64(data.count) == file.size, "\(file.name) size")
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(sha == file.sha256, "\(file.name) hash")
        }
        let version = try JSONDecoder().decode(
            BibleVersion.self,
            from: Data(contentsOf: RepositoryBibles.kjv.appendingPathComponent("version.json"))
        )
        #expect(version == entry.version)
    }

    @Test
    func publishedIDsAreUnique() {
        let ids = BibleCatalogEntry.published.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
