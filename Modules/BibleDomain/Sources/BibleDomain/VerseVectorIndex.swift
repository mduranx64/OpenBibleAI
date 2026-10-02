//
//  VerseVectorIndex.swift
//  BibleDomain
//

import Accelerate
import Foundation

/// Precomputed verse embeddings for semantic search, bundled with the app.
///
/// Binary layout (little-endian): `"OBVI"`, `UInt32` version, `UInt32`
/// header length, JSON `Header`, then one row per verse — `UInt8` book index
/// into `Header.books`, `UInt16` chapter, `UInt16` verse — then
/// `count × dimensions` Float16 values. Vectors are L2-normalised, so a dot
/// product with a normalised query is the cosine similarity.
public struct VerseVectorIndex: Sendable {
    public struct Header: Codable, Equatable, Sendable {
        /// Embedding model repository and pinned revision that produced the vectors.
        public let model: String
        public let revision: String
        public let dimensions: Int
        public let count: Int
        /// SHA-256 of the verse data the vectors were computed from.
        public let source: String
        public var books: [String]

        public init(model: String, revision: String, dimensions: Int, count: Int, source: String, books: [String] = []) {
            self.model = model
            self.revision = revision
            self.dimensions = dimensions
            self.count = count
            self.source = source
            self.books = books
        }
    }

    public enum FormatError: Error, Equatable, Sendable {
        case badMagic
        case unsupportedVersion(UInt32)
        case corruptHeader
        case sizeMismatch
        case countMismatch
        case dimensionMismatch
    }

    private static let magic = Data("OBVI".utf8)
    private static let version: UInt32 = 1
    private static let rowSize = 5

    public let header: Header
    private let references: [BibleReference]
    private let vectors: [Float]

    // MARK: - Reading

    public init(data: Data) throws(FormatError) {
        guard data.count >= 12, data.prefix(4) == Self.magic else { throw .badMagic }
        let version = data.readUInt32(at: 4)
        guard version == Self.version else { throw .unsupportedVersion(version) }
        let headerLength = Int(data.readUInt32(at: 8))
        guard data.count >= 12 + headerLength,
              let header = try? JSONDecoder().decode(Header.self, from: data.subdata(in: 12..<(12 + headerLength))),
              header.count >= 0, header.dimensions > 0
        else { throw .corruptHeader }

        let rowsStart = 12 + headerLength
        let vectorsStart = rowsStart + header.count * Self.rowSize
        let expected = vectorsStart + header.count * header.dimensions * 2
        guard data.count == expected else { throw .sizeMismatch }

        var references: [BibleReference] = []
        references.reserveCapacity(header.count)
        for row in 0..<header.count {
            let offset = rowsStart + row * Self.rowSize
            let bookIndex = Int(data[data.startIndex + offset])
            guard header.books.indices.contains(bookIndex),
                  let reference = try? BibleReference(
                      bookID: header.books[bookIndex],
                      chapter: Int(data.readUInt16(at: offset + 1)),
                      verse: Int(data.readUInt16(at: offset + 3))
                  )
            else { throw .corruptHeader }
            references.append(reference)
        }

        let halfs: [UInt16] = data.subdata(in: vectorsStart..<expected).withUnsafeBytes { raw in
            Array(raw.bindMemory(to: UInt16.self)).map { UInt16(littleEndian: $0) }
        }

        self.header = header
        self.references = references
        self.vectors = Self.floats(fromHalfs: halfs)
    }

    // MARK: - Writing

    /// Builds index data from verses in a fixed order with their vectors
    /// (normalised here). `header.count` must match `entries.count`.
    public static func encode(
        header: Header,
        entries: [(BibleReference, [Float])]
    ) throws(FormatError) -> Data {
        guard header.count == entries.count else { throw .countMismatch }
        guard entries.allSatisfy({ $0.1.count == header.dimensions }) else { throw .dimensionMismatch }

        var header = header
        var books: [String] = []
        var bookIndex: [String: Int] = [:]
        for (reference, _) in entries where bookIndex[reference.bookID] == nil {
            bookIndex[reference.bookID] = books.count
            books.append(reference.bookID)
        }
        guard books.count <= Int(UInt8.max) + 1 else { throw .corruptHeader }
        header.books = books

        guard let headerData = try? JSONEncoder().encode(header) else { throw .corruptHeader }

        var data = Self.magic
        data.appendUInt32(Self.version)
        data.appendUInt32(UInt32(headerData.count))
        data.append(headerData)

        for (reference, _) in entries {
            data.append(UInt8(bookIndex[reference.bookID]!))
            data.appendUInt16(UInt16(reference.chapter))
            data.appendUInt16(UInt16(reference.verse))
        }

        let normalised = entries.flatMap { normalised($0.1) }
        for half in halfs(fromFloats: normalised) {
            data.appendUInt16(half)
        }
        return data
    }

    /// The reference and (normalised) vector stored in `row`.
    public func entry(at row: Int) -> (BibleReference, [Float]) {
        let width = header.dimensions
        return (references[row], Array(vectors[(row * width)..<((row + 1) * width)]))
    }

    /// A smaller index using the first `dimensions` values of each vector,
    /// renormalised (valid for Matryoshka-trained embedding models).
    public func truncated(to dimensions: Int) throws(FormatError) -> VerseVectorIndex {
        guard dimensions > 0, dimensions <= header.dimensions else { throw .dimensionMismatch }
        let width = header.dimensions
        let entries = references.indices.map { row in
            (references[row], Array(vectors[(row * width)..<(row * width + dimensions)]))
        }
        let smaller = Header(
            model: header.model, revision: header.revision, dimensions: dimensions,
            count: header.count, source: header.source
        )
        return try VerseVectorIndex(data: Self.encode(header: smaller, entries: entries))
    }

    // MARK: - Search

    /// Verses most similar to `query` (any length vector of `dimensions`
    /// values; normalised here). Returns nothing if dimensions don't match.
    public func search(_ query: [Float], limit: Int) -> [RankedVerse] {
        let dimensions = header.dimensions
        guard query.count == dimensions, limit > 0, !references.isEmpty else { return [] }
        let unit = Self.normalised(query)

        var scores = [Float](repeating: 0, count: references.count)
        vectors.withUnsafeBufferPointer { matrix in
            unit.withUnsafeBufferPointer { vector in
                scores.withUnsafeMutableBufferPointer { result in
                    vDSP_mmul(
                        matrix.baseAddress!, 1, vector.baseAddress!, 1,
                        result.baseAddress!, 1,
                        vDSP_Length(references.count), 1, vDSP_Length(dimensions)
                    )
                }
            }
        }

        return scores.indices
            .sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
            .prefix(limit)
            .map { RankedVerse(reference: references[$0], score: Double(scores[$0])) }
    }

    // MARK: - Helpers

    static func normalised(_ vector: [Float]) -> [Float] {
        var sumOfSquares: Float = 0
        vDSP_svesq(vector, 1, &sumOfSquares, vDSP_Length(vector.count))
        let length = sumOfSquares.squareRoot()
        guard length > 0 else { return vector }
        return vector.map { $0 / length }
    }

    /// Float16 bits → Float32 via vImage (works on Intel Macs, unlike `Float16`).
    private static func floats(fromHalfs halfs: [UInt16]) -> [Float] {
        var input = halfs
        var output = [Float](repeating: 0, count: halfs.count)
        input.withUnsafeMutableBytes { source in
            output.withUnsafeMutableBytes { destination in
                var src = vImage_Buffer(data: source.baseAddress, height: 1, width: vImagePixelCount(halfs.count), rowBytes: source.count)
                var dst = vImage_Buffer(data: destination.baseAddress, height: 1, width: vImagePixelCount(halfs.count), rowBytes: destination.count)
                _ = vImageConvert_Planar16FtoPlanarF(&src, &dst, vImage_Flags(kvImageNoFlags))
            }
        }
        return output
    }

    private static func halfs(fromFloats floats: [Float]) -> [UInt16] {
        var input = floats
        var output = [UInt16](repeating: 0, count: floats.count)
        input.withUnsafeMutableBytes { source in
            output.withUnsafeMutableBytes { destination in
                var src = vImage_Buffer(data: source.baseAddress, height: 1, width: vImagePixelCount(floats.count), rowBytes: source.count)
                var dst = vImage_Buffer(data: destination.baseAddress, height: 1, width: vImagePixelCount(floats.count), rowBytes: destination.count)
                _ = vImageConvert_PlanarFtoPlanar16F(&src, &dst, vImage_Flags(kvImageNoFlags))
            }
        }
        return output
    }
}

/// Merges rankings (e.g. keyword and semantic) by reciprocal rank fusion:
/// each verse scores Σ 1 / (k + rank) over the lists it appears in.
public enum RankFusion {
    public static func reciprocalRank(
        _ lists: [[RankedVerse]],
        k: Double = 60,
        limit: Int
    ) -> [RankedVerse] {
        var scores: [BibleReference: Double] = [:]
        var firstSeen: [BibleReference: Int] = [:]
        var order = 0
        for list in lists {
            for (rank, item) in list.enumerated() {
                scores[item.reference, default: 0] += 1 / (k + Double(rank + 1))
                if firstSeen[item.reference] == nil {
                    firstSeen[item.reference] = order
                    order += 1
                }
            }
        }
        return scores
            .sorted { $0.value != $1.value ? $0.value > $1.value : firstSeen[$0.key]! < firstSeen[$1.key]! }
            .prefix(limit)
            .map { RankedVerse(reference: $0.key, score: $0.value) }
    }
}

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * UInt32($1)) }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) })
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}
