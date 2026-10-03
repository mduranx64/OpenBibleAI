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
/// into `Header.books`, `UInt16` chapter, `UInt16` verse — then the vectors:
/// version 1 stores `count × dimensions` Float16 values; version 2 stores one
/// `Float32` scale per verse, then `count × dimensions` `Int8` values
/// (value × scale / 127), half the size. Vectors are L2-normalised, so a dot
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

    /// How vector values are stored.
    public enum Precision: Sendable {
        /// Version 1: 2 bytes per value.
        case float16
        /// Version 2: 1 byte per value plus a scale per verse.
        case int8
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
    private static let rowSize = 5

    public let header: Header
    private let references: [BibleReference]
    private let vectors: [Float]

    // MARK: - Reading

    public init(data: Data) throws(FormatError) {
        guard data.count >= 12, data.prefix(4) == Self.magic else { throw .badMagic }
        let version = data.readUInt32(at: 4)
        guard version == 1 || version == 2 else { throw .unsupportedVersion(version) }
        let headerLength = Int(data.readUInt32(at: 8))
        guard data.count >= 12 + headerLength,
              let header = try? JSONDecoder().decode(Header.self, from: data.subdata(in: 12..<(12 + headerLength))),
              header.count >= 0, header.dimensions > 0
        else { throw .corruptHeader }

        let rowsStart = 12 + headerLength
        let vectorsStart = rowsStart + header.count * Self.rowSize
        let values = header.count * header.dimensions
        let expected = vectorsStart + (version == 1 ? values * 2 : header.count * 4 + values)
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

        self.header = header
        self.references = references
        if version == 1 {
            let halfs: [UInt16] = data.subdata(in: vectorsStart..<expected).withUnsafeBytes { raw in
                Array(raw.bindMemory(to: UInt16.self)).map { UInt16(littleEndian: $0) }
            }
            self.vectors = Self.floats(fromHalfs: halfs)
        } else {
            let scalesEnd = vectorsStart + header.count * 4
            let scales: [Float] = data.subdata(in: vectorsStart..<scalesEnd).withUnsafeBytes { raw in
                Array(raw.bindMemory(to: UInt32.self)).map { Float(bitPattern: UInt32(littleEndian: $0)) }
            }
            let quantized: [Int8] = data.subdata(in: scalesEnd..<expected).withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Int8.self))
            }
            self.vectors = Self.floats(fromQuantized: quantized, scales: scales, dimensions: header.dimensions)
        }
    }

    // MARK: - Writing

    /// Builds index data from verses in a fixed order with their vectors
    /// (normalised here). `header.count` must match `entries.count`.
    public static func encode(
        header: Header,
        entries: [(BibleReference, [Float])],
        precision: Precision = .float16
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
        data.appendUInt32(precision == .float16 ? 1 : 2)
        data.appendUInt32(UInt32(headerData.count))
        data.append(headerData)

        for (reference, _) in entries {
            data.append(UInt8(bookIndex[reference.bookID]!))
            data.appendUInt16(UInt16(reference.chapter))
            data.appendUInt16(UInt16(reference.verse))
        }

        switch precision {
        case .float16:
            let normalised = entries.flatMap { normalised($0.1) }
            for half in halfs(fromFloats: normalised) {
                data.appendUInt16(half)
            }
        case .int8:
            let rows = entries.map { quantized(normalised($0.1)) }
            for row in rows {
                data.appendUInt32(row.scale.bitPattern)
            }
            for row in rows {
                data.append(contentsOf: row.values.map { UInt8(bitPattern: $0) })
            }
        }
        return data
    }

    /// The reference and (normalised) vector stored in `row`.
    public func entry(at row: Int) -> (BibleReference, [Float]) {
        let width = header.dimensions
        return (references[row], Array(vectors[(row * width)..<((row + 1) * width)]))
    }

    /// The same index stored with another precision (e.g. a Float16 index
    /// re-encoded as int8).
    public func encoded(as precision: Precision) throws(FormatError) -> Data {
        let unannotated = Header(
            model: header.model, revision: header.revision, dimensions: header.dimensions,
            count: header.count, source: header.source
        )
        return try Self.encode(header: unannotated, entries: references.indices.map(entry(at:)), precision: precision)
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

    /// Symmetric int8 quantization of one normalised vector: the largest
    /// magnitude maps to ±127.
    private static func quantized(_ vector: [Float]) -> (scale: Float, values: [Int8]) {
        let largest = vector.map(abs).max() ?? 0
        guard largest > 0 else { return (0, vector.map { _ in 0 }) }
        return (largest, vector.map { Int8(($0 / largest * 127).rounded()) })
    }

    private static func floats(fromQuantized values: [Int8], scales: [Float], dimensions: Int) -> [Float] {
        var output = [Float](repeating: 0, count: values.count)
        for row in scales.indices {
            let factor = scales[row] / 127
            for column in 0..<dimensions {
                let index = row * dimensions + column
                output[index] = Float(values[index]) * factor
            }
        }
        return output
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
