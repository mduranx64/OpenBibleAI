//
//  BibleVersionPackageTests.swift
//  BibleData
//

import Foundation
import Testing
import BibleData
import BibleDomain

struct BibleVersionPackageTests {
    private func makePackage(embeddings: Bool, omitting: String? = nil) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BibleVersionPackageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = [
            BibleVersionPackage.FileName.version: """
            {"id":"rv1909","name":"Reina-Valera 1909","abbreviation":"RV1909","language":"es","copyright":"Dominio público"}
            """,
            BibleVersionPackage.FileName.books: """
            [{"book_id":"JHN","name":"Juan","canonical_order":43}]
            """,
            BibleVersionPackage.FileName.verses: """
            [{"book_id":"JHN","chapter":9,"verse":1,"text":"Y pasando Jesús, vió un hombre ciego desde su nacimiento."},
             {"book_id":"JHN","chapter":9,"verse":2,"text":"Y preguntáronle sus discípulos, diciendo: Rabbí, ¿quién pecó?"}]
            """,
        ]
        for (name, text) in files where name != omitting {
            try Data(text.utf8).write(to: directory.appendingPathComponent(name))
        }
        if embeddings {
            try Data("OBVI".utf8).write(to: directory.appendingPathComponent(BibleVersionPackage.FileName.embeddings))
        }
        return directory
    }

    @Test
    func loadsMetadataBooksVersesAndLanguageRanking() async throws {
        let directory = try makePackage(embeddings: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let package = try await BibleVersionPackage.load(from: directory)

        #expect(package.version.id == "rv1909")
        #expect(package.version.languageCode == "es")
        #expect(package.books.map(\.name) == ["Juan"])
        #expect(package.embeddingsURL == nil)

        let reference = try BibleReference(bookID: "JHN", chapter: 9, verse: 1)
        #expect(try await package.repository.verse(at: reference).text.hasPrefix("Y pasando Jesús"))
        // Spanish rules: "ciegos" matches "ciego".
        let ranked = try await package.repository.rankedVerses(matching: ["ciegos"], limit: 5)
        #expect(ranked.map(\.reference) == [reference])
    }

    @Test
    func reportsTheEmbeddingIndexWhenPresent() async throws {
        let directory = try makePackage(embeddings: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let package = try await BibleVersionPackage.load(from: directory)
        #expect(package.embeddingsURL?.lastPathComponent == BibleVersionPackage.FileName.embeddings)
    }

    @Test(arguments: [BibleVersionPackage.FileName.version, BibleVersionPackage.FileName.books, BibleVersionPackage.FileName.verses])
    func missingRequiredFilesFail(name: String) async throws {
        let directory = try makePackage(embeddings: false, omitting: name)
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: BibleVersionPackage.LoadError.missingFile(name)) {
            try await BibleVersionPackage.load(from: directory)
        }
    }
}

struct RepositoryKJVPackageTests {
    @Test
    func theVersionedKJVPackageLoads() async throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Bibles/kjv")

        let package = try await BibleVersionPackage.load(from: directory)

        #expect(package.version.id == "kjv")
        #expect(package.books.count == 66)
        #expect(package.embeddingsURL != nil)
        let verse = try await package.repository.verse(at: BibleReference(bookID: "JOH", chapter: 3, verse: 16))
        #expect(verse.text.contains("For God so loved the world"))
    }
}
