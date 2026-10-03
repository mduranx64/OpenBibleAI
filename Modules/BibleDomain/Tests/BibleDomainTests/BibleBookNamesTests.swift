//
//  BibleBookNamesTests.swift
//  BibleDomain
//

import Foundation
import Testing
import BibleDomain

/// The alias tables agree with the import tool's book tables, and no name
/// means different books in different languages.
struct BibleBookNamesTests {
    private static let books = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../../../Tools/BibleImport/books")
        .standardized

    private static func table(_ name: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: books.appendingPathComponent("\(name).json")))
    }

    @Test
    func theTablesAreTheImportTables() throws {
        let english = try Self.table("en")
        #expect(BibleBookNames.english.filter { english[$0.key] != nil } == english)
        #expect(BibleBookNames.spanish == (try Self.table("es")))
        #expect(BibleBookNames.portuguese == (try Self.table("pt")))
    }

    @Test
    func everyAliasResolvesToItsOwnBookInEveryLanguage() throws {
        for language in ["en", "es", "pt"] {
            let table = try Self.table(language)
            let books = try table.keys.sorted().enumerated().map {
                try BibleBook(bookID: $0.element, name: table[$0.element]!, canonicalOrder: $0.offset + 1)
            }
            for (id, names) in BibleBookNames.aliases where table[id] != nil {
                for name in names {
                    let reference = try BibleReferenceParser.parse("\(name) 1:1", books: books, aliases: BibleBookNames.aliases)
                    #expect(reference.bookID == id, "\(language): \(name)")
                }
            }
        }
    }
}
