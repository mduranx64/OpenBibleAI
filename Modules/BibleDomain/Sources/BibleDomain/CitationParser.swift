//
//  CitationParser.swift
//  BibleDomain
//

import Foundation

/// A bracketed citation in generated text, e.g. `[Matthew 2:1]`,
/// `[Luke 2:4-7]` or `[John 9:1-7; 1 John 1:5]`.
public struct Citation: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        /// A resolved reference; `endVerse` is set for ranges in one chapter.
        case reference(BibleReference, endVerse: Int?)
        /// Looked like a citation but did not resolve (unknown book, bad range).
        case unrecognized(String)
    }

    /// Range of the whole bracketed text, including the brackets.
    public let range: Range<String.Index>
    public let items: [Item]
}

/// Finds citations in generated answers so they can be checked against the
/// Bible and turned into links. Names must be full catalog names (the answer
/// prompt asks for them); resolution reuses `BibleReferenceParser`.
public enum CitationParser {
    public static func citations(in text: String, books: [BibleBook]) -> [Citation] {
        var result: [Citation] = []
        var searchStart = text.startIndex

        while let open = text[searchStart...].firstIndex(of: "["),
              let close = text[text.index(after: open)...].firstIndex(of: "]") {
            let inner = text[text.index(after: open)..<close]
            searchStart = text.index(after: close)

            // Only brackets with letters and digits are citations; KJV
            // supplied words like "[of]" are not.
            guard inner.contains(where: \.isNumber), inner.contains(where: \.isLetter),
                  !inner.contains("[")
            else { continue }

            let items = inner
                .split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { item(for: $0, books: books) }

            result.append(Citation(range: open..<text.index(after: close), items: items))
        }

        result += bareCitations(in: text, books: books, excluding: result.map(\.range))
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Unbracketed references like "Luke 2:4" or "1 John 4:8-9". Small models
    /// often cite this way despite the prompt. Only catalog names followed by
    /// `chapter:verse` count; longer names are matched first so "1 John" is
    /// not read as "John", and text inside bracketed citations is skipped.
    private static func bareCitations(
        in text: String,
        books: [BibleBook],
        excluding claimed: [Range<String.Index>]
    ) -> [Citation] {
        var claimed = claimed
        var found: [Citation] = []

        for book in books.sorted(by: { $0.name.count > $1.name.count }) {
            var searchStart = text.startIndex
            while let nameRange = text.range(of: book.name, range: searchStart..<text.endIndex) {
                searchStart = nameRange.upperBound
                guard nameRange.lowerBound == text.startIndex
                        || !isWordCharacter(text[text.index(before: nameRange.lowerBound)]),
                      let end = positionEnd(in: text, after: nameRange.upperBound)
                else { continue }

                let range = nameRange.lowerBound..<end
                guard !claimed.contains(where: { $0.overlaps(range) }) else { continue }

                let item = item(for: String(text[range]), books: books)
                guard case .reference = item else { continue }
                claimed.append(range)
                found.append(Citation(range: range, items: [item]))
            }
        }
        return found
    }

    /// End of " C:V" or " C:V-V" right after a name, or nil if absent.
    private static func positionEnd(in text: String, after nameEnd: String.Index) -> String.Index? {
        var index = nameEnd
        guard index < text.endIndex, text[index] == " " else { return nil }
        index = text.index(after: index)

        func digits() -> Bool {
            let start = index
            while index < text.endIndex, text[index].isASCII, text[index].isNumber {
                index = text.index(after: index)
            }
            return index > start
        }

        guard digits(), index < text.endIndex, text[index] == ":" else { return nil }
        index = text.index(after: index)
        guard digits() else { return nil }

        if index < text.endIndex, text[index] == "-" || text[index] == "–" {
            let rangeStart = index
            index = text.index(after: index)
            if !digits() { index = rangeStart }
        }
        guard index == text.endIndex || !isWordCharacter(text[index]) else { return nil }
        return index
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func item(for part: String, books: [BibleBook]) -> Citation.Item {
        guard let space = part.lastIndex(where: \.isWhitespace) else { return .unrecognized(part) }
        let name = part[..<space].trimmingCharacters(in: .whitespaces)
        let position = part[part.index(after: space)...]
        let chapterAndVerses = position.split(separator: ":", maxSplits: 1)
        guard !name.isEmpty, chapterAndVerses.count == 2 else { return .unrecognized(part) }

        let verses = chapterAndVerses[1].split(whereSeparator: { $0 == "-" || $0 == "–" })
        guard let chapter = Int(chapterAndVerses[0]),
              (1...2).contains(verses.count),
              let first = Int(verses[0])
        else { return .unrecognized(part) }

        let last = verses.count == 2 ? Int(verses[1]) : nil
        if verses.count == 2, (last ?? 0) < first { return .unrecognized(part) }

        guard let reference = try? BibleReferenceParser.parse("\(name) \(chapter):\(first)", books: books)
        else { return .unrecognized(part) }

        return .reference(reference, endVerse: last == first ? nil : last)
    }
}
