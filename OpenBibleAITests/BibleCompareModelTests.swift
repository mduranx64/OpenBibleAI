import BibleAI
import BibleDomain
import Foundation
import Testing
@testable import OpenBibleAI

@MainActor
struct BibleCompareModelTests {
    private static func verse(_ book: String, _ chapter: Int, _ number: Int, _ text: String) throws -> BibleVerse {
        try BibleVerse(reference: BibleReference(bookID: book, chapter: chapter, verse: number), text: text)
    }

    private static func entry(_ id: String) throws -> BibleCatalogEntry {
        BibleCatalogEntry(
            version: try BibleVersion(id: id, name: id.uppercased(), abbreviation: id.uppercased(), languageCode: "en", copyright: ""),
            manifest: ModelManifest(repository: "owner/repo", revision: id, files: [], host: .gitHubRelease(tag: "bibles"))
        )
    }

    /// kjv, rv and web installed; rv lacks JHN 3:2 and web has an extra 3:4.
    private func makeLibrary(defaults: InMemoryDefaults = InMemoryDefaults()) throws -> BibleLibraryModel {
        let texts: [String: [BibleVerse]] = [
            "kjv": [try Self.verse("JHN", 3, 1, "K1"), try Self.verse("JHN", 3, 2, "K2"), try Self.verse("JHN", 3, 3, "K3")],
            "rv": [try Self.verse("JHN", 3, 1, "R1"), try Self.verse("JHN", 3, 3, "R3")],
            "web": [try Self.verse("JHN", 3, 1, "W1"), try Self.verse("JHN", 3, 2, "W2"), try Self.verse("JHN", 3, 3, "W3"), try Self.verse("JHN", 3, 4, "W4")],
        ]
        let catalog = try ["kjv", "rv", "web"].map(Self.entry)
        var stores: [String: any LocalModelStoring] = [:]
        for entry in catalog { stores[entry.id] = FakeBibleStore(id: entry.id, installed: true) }
        return BibleLibraryModel(catalog: catalog, stores: stores, defaults: defaults) { entry, _ in
            LoadedBible(
                version: entry.version,
                repositories: AppModel.Repositories(repository: InMemoryBibleRepository(verses: texts[entry.id] ?? [])),
                embeddingsURL: nil
            )
        }
    }

    @Test
    func rowsAlignByVerseNumberWithGapsForMissingVerses() async throws {
        let library = try makeLibrary()
        await library.refresh()
        let model = BibleCompareModel(library: library, defaults: InMemoryDefaults())
        model.add("rv")
        model.add("web")

        let primary = try ["P1", "P2", "P3"].enumerated().map { try Self.verse("JHN", 3, $0.offset + 1, $0.element) }
        await model.load(bookID: "JHN", chapter: 3, primary: primary, primaryVersionID: "kjv")

        #expect(model.columnIDs(excluding: "kjv") == ["rv", "web"])
        #expect(model.rows.map(\.verse) == [1, 2, 3, 4])
        #expect(model.rows.map(\.texts) == [
            ["P1", "R1", "W1"],
            ["P2", nil, "W2"],
            ["P3", "R3", "W3"],
            [nil, nil, "W4"],
        ])
    }

    @Test
    func columnsAreLimitedUniqueAndSaved() async throws {
        let defaults = InMemoryDefaults()
        let library = try makeLibrary()
        await library.refresh()
        let model = BibleCompareModel(library: library, defaults: defaults)
        model.add("rv")
        model.add("rv")
        model.add("web")
        model.add("kjv")
        model.add("nope")
        #expect(model.columns == ["rv", "web", "kjv"], "Unique, installed, at most three extra")
        #expect(model.canAdd == false)

        model.remove("web")
        let restored = BibleCompareModel(library: library, defaults: defaults)
        #expect(restored.columns == ["rv", "kjv"])
    }

    @Test
    func thePrimaryVersionIsNotRepeatedAsAColumn() async throws {
        let library = try makeLibrary()
        await library.refresh()
        let model = BibleCompareModel(library: library, defaults: InMemoryDefaults())
        model.add("rv")
        model.add("kjv")

        #expect(model.columnIDs(excluding: "kjv") == ["rv"])
        #expect(model.isComparing(primaryVersionID: "kjv"))
        #expect(model.columnIDs(excluding: "rv") == ["kjv"])
    }

    @Test
    func aNewerLoadWinsOverAnOlderOne() async throws {
        let library = try makeLibrary()
        await library.refresh()
        let model = BibleCompareModel(library: library, defaults: InMemoryDefaults())
        model.add("web")

        let first = try [Self.verse("JHN", 3, 1, "old")]
        let second = try [Self.verse("JHN", 3, 1, "new")]
        async let a: Void = model.load(bookID: "JHN", chapter: 3, primary: first, primaryVersionID: "kjv")
        async let b: Void = model.load(bookID: "JHN", chapter: 3, primary: second, primaryVersionID: "kjv")
        _ = await (a, b)

        #expect(model.rows.first?.texts.first == "new")
    }
}
