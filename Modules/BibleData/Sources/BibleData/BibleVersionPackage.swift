//
//  BibleVersionPackage.swift
//  BibleData
//

import Foundation
import BibleDomain

/// One installed Bible version, read from its folder:
///
/// - `version.json`: `BibleVersion` metadata (id, name, abbreviation, language, copyright)
/// - `books.json`: books in the version's language (same format as the KJV catalog)
/// - `verses.json`: verses (same format as the KJV verses)
/// - `embeddings.bin`: optional `VerseVectorIndex` for semantic search, loaded on demand
public struct BibleVersionPackage: Sendable {
    public enum FileName {
        public static let version = "version.json"
        public static let books = "books.json"
        public static let verses = "verses.json"
        public static let embeddings = "embeddings.bin"
    }

    public let version: BibleVersion
    public let books: [BibleBook]
    public let repository: JSONBibleRepository
    /// The verse-embedding index, when the package has one.
    public let embeddingsURL: URL?

    public enum LoadError: Error, Equatable, Sendable {
        case missingFile(String)
    }

    /// Reads and validates the package off the caller's actor.
    @concurrent
    public static func load(from directory: URL) async throws -> Self {
        let fileManager = FileManager.default
        func file(_ name: String) throws -> URL {
            let url = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { throw LoadError.missingFile(name) }
            return url
        }

        try Task.checkCancellation()
        let version = try JSONDecoder().decode(
            BibleVersion.self,
            from: Data(contentsOf: file(FileName.version))
        )
        let catalog = try await JSONBibleBookCatalog.load(from: file(FileName.books))
        let repository = try await JSONBibleRepository.load(
            from: file(FileName.verses),
            books: catalog.books,
            language: version.languageCode
        )
        let embeddings = directory.appendingPathComponent(FileName.embeddings)

        return BibleVersionPackage(
            version: version,
            books: catalog.books,
            repository: repository,
            embeddingsURL: fileManager.fileExists(atPath: embeddings.path) ? embeddings : nil
        )
    }
}
