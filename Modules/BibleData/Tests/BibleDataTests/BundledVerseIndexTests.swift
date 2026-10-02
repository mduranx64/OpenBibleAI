//
//  BundledVerseIndexTests.swift
//  BibleData
//

import CryptoKit
import Foundation
import Testing
import BibleData
import BibleDomain

/// The bundled semantic index must describe exactly the bundled KJV. If the
/// verses or the embedding model change, rebuild it (see DEVELOPMENT.md).
struct BundledVerseIndexTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Bibles/kjv")

    @Test
    func bundledIndexMatchesTheBundledBibleAndPinnedModel() async throws {
        let versesData = try Data(contentsOf: Self.resources.appendingPathComponent("verses.json"))
        let index = try VerseVectorIndex(data: Data(contentsOf: Self.resources.appendingPathComponent("embeddings.bin")))

        let sha = SHA256.hash(data: versesData).map { String(format: "%02x", $0) }.joined()
        #expect(index.header.source == sha, "Index was built from different verse data; rebuild it")
        #expect(index.header.model == "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
        #expect(index.header.revision == "6c3ae70858513f1a78e9cdca3cae330d9075cd2a")
        #expect(index.header.dimensions == 256)
        #expect(index.header.count == 31_102)

        let books = try JSONBibleBookCatalog(data: Data(contentsOf: Self.resources.appendingPathComponent("books.json"))).books
        let repository = try JSONBibleRepository(data: versesData, books: books)
        let indexed = Set((0..<index.header.count).map { index.entry(at: $0).0 })
        #expect(indexed.count == 31_102)
        for reference in [indexed.first!, try BibleReference(bookID: "REV", chapter: 22, verse: 21)] {
            #expect(indexed.contains(reference))
            _ = try await repository.verse(at: reference)
        }
    }
}
