//
//  TextAnalyzerTests.swift
//  BibleDomain
//

import Foundation
import Testing
import BibleDomain

struct TextAnalyzerTests {
    @Test
    func englishMatchesTheKJVTokens() {
        for text in ["Where was Jesus born?", "And he healed them; he healeth, healing", "blind eyes"] {
            #expect(TextAnalyzer.english.tokens(in: text) == RankedVerseIndex.tokens(in: text))
        }
    }

    @Test
    func spanishDropsStopWordsAndFoldsGenderNumberAndParticiples() {
        let spanish = TextAnalyzer.spanish
        #expect(spanish.tokens(in: "¿Dónde está el ciego?") == ["cieg"])
        #expect(Set(["ciegos", "ciega", "ciego"].flatMap(spanish.tokens(in:))) == ["cieg"])
        #expect(Set(["sanó", "sanado", "sanados", "sana"].flatMap(spanish.tokens(in:))) == ["san"])
        #expect(spanish.tokens(in: "Jesús y Moisés dijeron a Dios") == ["jesus", "moises", "dios"])
    }

    @Test
    func portugueseDropsStopWordsAndFoldsGenderNumberAndParticiples() {
        let portuguese = TextAnalyzer.portuguese
        #expect(portuguese.tokens(in: "Onde está o cego?") == ["ceg"])
        #expect(Set(["cegos", "cega", "cego"].flatMap(portuguese.tokens(in:))) == ["ceg"])
        #expect(Set(["curou", "curado", "curados", "cura"].flatMap(portuguese.tokens(in:))) == ["cur"])
        #expect(Set(["corações", "coração"].flatMap(portuguese.tokens(in:))).count == 1)
        #expect(portuguese.tokens(in: "Jesus e Deus") == ["jesus", "deus"])
    }

    @Test
    func unknownLanguagesKeepEveryFoldedWord() {
        #expect(TextAnalyzer(languageCode: "de").tokens(in: "Der Herr ist mein Hirte") == ["der", "herr", "ist", "mein", "hirte"])
    }

    @Test
    func languageCodesPickTheAnalyzer() {
        #expect(TextAnalyzer(languageCode: "en") == .english)
        #expect(TextAnalyzer(languageCode: "es-419") == .spanish)
        #expect(TextAnalyzer(languageCode: "pt-BR") == .portuguese)
    }

    @Test
    func spanishRankingFindsInflectedForms() async throws {
        let repository = InMemoryBibleRepository(
            verses: [
                try BibleVerse(reference: BibleReference(bookID: "JHN", chapter: 9, verse: 1), text: "Y pasando Jesús, vio a un hombre ciego desde su nacimiento."),
                try BibleVerse(reference: BibleReference(bookID: "JHN", chapter: 9, verse: 2), text: "Y le preguntaron sus discípulos, diciendo: Rabí, ¿quién pecó?"),
                try BibleVerse(reference: BibleReference(bookID: "MAT", chapter: 1, verse: 1), text: "Libro de la generación de Jesucristo."),
            ],
            language: "es"
        )
        let ranked = try await repository.rankedVerses(matching: ["ciegos"], limit: 2)
        #expect(ranked.map(\.reference.verse) == [1])
    }
}

struct BibleVersionTests {
    @Test
    func versionValidatesAndDecodesMetadata() throws {
        let json = """
        {"id":"rv1909","name":"Reina-Valera 1909","abbreviation":"RV1909","language":"es","copyright":"Public domain"}
        """
        let version = try JSONDecoder().decode(BibleVersion.self, from: Data(json.utf8))
        #expect(version.id == "rv1909")
        #expect(version.languageCode == "es")
        #expect(version.analyzer == .spanish)

        #expect(throws: BibleVersion.ValidationError.blankID) {
            try BibleVersion(id: " ", name: "X", abbreviation: "X", languageCode: "en", copyright: "")
        }
        #expect(throws: BibleVersion.ValidationError.blankName) {
            try BibleVersion(id: "x", name: "", abbreviation: "X", languageCode: "en", copyright: "")
        }
    }
}
