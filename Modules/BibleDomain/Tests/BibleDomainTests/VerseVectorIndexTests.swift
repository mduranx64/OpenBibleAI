//
//  VerseVectorIndexTests.swift
//  BibleDomain
//

import Foundation
import Testing
import BibleDomain

struct VerseVectorIndexTests {
    private func ref(_ book: String, _ chapter: Int, _ verse: Int) throws -> BibleReference {
        try BibleReference(bookID: book, chapter: chapter, verse: verse)
    }

    private func header(count: Int, dimensions: Int = 3) -> VerseVectorIndex.Header {
        VerseVectorIndex.Header(
            model: "test/model", revision: "abc", dimensions: dimensions,
            count: count, source: "sha"
        )
    }

    private func entries() throws -> [(BibleReference, [Float])] {
        [
            (try ref("GEN", 1, 1), [1, 0, 0]),
            (try ref("MAT", 2, 1), [0, 1, 0]),
            (try ref("JOH", 9, 7), [0, 0.6, 0.8]),
        ]
    }

    @Test
    func encodedIndexRoundTripsAndRanksByCosine() throws {
        let data = try VerseVectorIndex.encode(header: header(count: 3), entries: entries())
        let index = try VerseVectorIndex(data: data)

        var expected = header(count: 3)
        expected.books = ["GEN", "MAT", "JOH"]  // filled in by encode, in first-seen order
        #expect(index.header == expected)
        let ranked = index.search([0, 2, 0.1], limit: 2)   // query is normalised
        #expect(ranked.map(\.reference) == [try ref("MAT", 2, 1), try ref("JOH", 9, 7)])
        #expect(ranked[0].score > ranked[1].score)
        #expect(abs(ranked[0].score - 0.9988) < 0.01, "Float16 storage keeps cosine accurate")
    }

    /// Deterministic pseudo-random vectors, like real embeddings (no zeros).
    private func manyEntries(count: Int, dimensions: Int) throws -> [(BibleReference, [Float])] {
        var seed: UInt64 = 42
        func next() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: seed >> 11) % 2_000) / 1_000 - 1
        }
        return try (0..<count).map { row in
            (try ref("PSA", row / 150 + 1, row % 150 + 1), (0..<dimensions).map { _ in next() })
        }
    }

    @Test
    func int8IndexIsHalfTheSizeAndRanksLikeFloat16() throws {
        let entries = try manyEntries(count: 300, dimensions: 64)
        let header = header(count: 300, dimensions: 64)
        let halfData = try VerseVectorIndex.encode(header: header, entries: entries)
        let byteData = try VerseVectorIndex.encode(header: header, entries: entries, precision: .int8)
        let half = try VerseVectorIndex(data: halfData)
        let byte = try VerseVectorIndex(data: byteData)

        #expect(Double(byteData.count) < Double(halfData.count) * 0.6)
        for row in [0, 77, 299] {
            let (reference, stored) = half.entry(at: row)
            let (sameReference, quantized) = byte.entry(at: row)
            #expect(reference == sameReference)
            let cosine = zip(stored, quantized).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            #expect(cosine > 0.999, "row \(row): \(cosine)")
        }
        for query in try manyEntries(count: 5, dimensions: 64).map(\.1) {
            #expect(byte.search(query, limit: 5).map(\.reference) == half.search(query, limit: 5).map(\.reference))
        }
    }

    @Test
    func aFloat16IndexReencodesAsInt8() throws {
        let half = try VerseVectorIndex(data: VerseVectorIndex.encode(header: header(count: 3), entries: entries()))

        let byte = try VerseVectorIndex(data: half.encoded(as: .int8))

        #expect(byte.header == half.header)
        #expect(byte.search([0, 2, 0.1], limit: 3).map(\.reference) == half.search([0, 2, 0.1], limit: 3).map(\.reference))
        #expect(throws: VerseVectorIndex.FormatError.sizeMismatch) {
            try VerseVectorIndex(data: half.encoded(as: .int8).dropLast())
        }
    }

    @Test
    func truncationKeepsLeadingDimensionsAndRenormalises() throws {
        let index = try VerseVectorIndex(data: VerseVectorIndex.encode(header: header(count: 3), entries: entries()))

        let small = try index.truncated(to: 2)

        #expect(small.header.dimensions == 2)
        #expect(small.header.count == 3)
        // JOH 9:7 was (0, 0.6, 0.8) → (0, 0.6) → (0, 1) after renormalising.
        let top = small.search([0, 1], limit: 2).map(\.reference)
        #expect(Set(top) == Set([try ref("MAT", 2, 1), try ref("JOH", 9, 7)]))
        #expect(throws: VerseVectorIndex.FormatError.dimensionMismatch) { try index.truncated(to: 4) }
    }

    @Test
    func wrongQueryDimensionsReturnNothing() throws {
        let index = try VerseVectorIndex(data: VerseVectorIndex.encode(header: header(count: 3), entries: entries()))
        #expect(index.search([1, 0], limit: 3).isEmpty)
    }

    @Test
    func corruptOrMismatchedDataIsRejected() throws {
        let good = try VerseVectorIndex.encode(header: header(count: 3), entries: entries())

        #expect(throws: VerseVectorIndex.FormatError.badMagic) {
            try VerseVectorIndex(data: Data("NOPE".utf8) + good.dropFirst(4))
        }
        #expect(throws: VerseVectorIndex.FormatError.sizeMismatch) {
            try VerseVectorIndex(data: good.dropLast(2))
        }
        #expect(throws: VerseVectorIndex.FormatError.countMismatch) {
            try VerseVectorIndex.encode(header: header(count: 5), entries: entries())
        }
    }
}

struct RankFusionTests {
    private func ranked(_ verses: [Int]) throws -> [RankedVerse] {
        try verses.enumerated().map { offset, verse in
            RankedVerse(reference: try BibleReference(bookID: "JOH", chapter: 9, verse: verse), score: Double(100 - offset))
        }
    }

    @Test
    func reciprocalRankFusionFavoursVersesRankedWellInBothLists() throws {
        let keyword = try ranked([1, 2, 3, 4])
        let semantic = try ranked([7, 3, 1, 9])

        let fused = RankFusion.reciprocalRank([keyword, semantic], limit: 3).map(\.reference.verse)

        #expect(fused == [1, 3, 7])
    }

    @Test
    func singleListKeepsItsOrderAndEmptyListsAreIgnored() throws {
        let keyword = try ranked([5, 6])
        #expect(RankFusion.reciprocalRank([keyword, []], limit: 5).map(\.reference.verse) == [5, 6])
    }
}
