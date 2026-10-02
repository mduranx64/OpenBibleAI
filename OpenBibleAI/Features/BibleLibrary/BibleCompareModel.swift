//
//  BibleCompareModel.swift
//  OpenBibleAI
//

import BibleDomain
import Foundation
import Observation

/// Side-by-side comparison of the reading version with up to three other
/// installed versions: the same chapter in each, aligned by verse number
/// (a verse one version numbers differently shows as a gap). The chosen
/// columns are remembered.
@MainActor
@Observable
final class BibleCompareModel {
    struct Row: Identifiable, Equatable {
        let verse: Int
        /// Primary version first, then each column; nil where a version has no such verse.
        let texts: [String?]
        var id: Int { verse }
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let maximumColumns = 3

    /// Extra versions shown next to the reading version, in order.
    private(set) var columns: [String]
    private(set) var rows: [Row] = []
    private(set) var state: State = .idle

    @ObservationIgnored private let library: BibleLibraryModel
    @ObservationIgnored private let defaults: any ReadingPositionStorage
    @ObservationIgnored private var generation = 0

    private static let columnsKey = "bible.compareVersions"

    init(library: BibleLibraryModel, defaults: any ReadingPositionStorage) {
        self.library = library
        self.defaults = defaults
        self.columns = defaults.data(forKey: Self.columnsKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    /// The columns to show next to `primaryVersionID` (installed, not the primary).
    func columnIDs(excluding primaryVersionID: String) -> [String] {
        columns.filter { $0 != primaryVersionID && library.installedIDs.contains($0) }
    }

    func isComparing(primaryVersionID: String) -> Bool {
        !columnIDs(excluding: primaryVersionID).isEmpty
    }

    var canAdd: Bool {
        columns.count < Self.maximumColumns
    }

    func add(_ id: String) {
        guard canAdd, !columns.contains(id), library.installedIDs.contains(id) else { return }
        columns.append(id)
        save()
    }

    func remove(_ id: String) {
        columns.removeAll { $0 == id }
        save()
    }

    /// Replaces a column's version, keeping its position.
    func replace(_ id: String, with replacement: String) {
        guard let index = columns.firstIndex(of: id), !columns.contains(replacement),
              library.installedIDs.contains(replacement)
        else { return }
        columns[index] = replacement
        save()
    }

    func closeAll() {
        columns = []
        save()
    }

    /// Loads the chapter from every column's version and aligns it with
    /// the primary verses already shown. Older loads never overwrite newer.
    func load(bookID: String, chapter: Int, primary: [BibleVerse], primaryVersionID: String) async {
        generation += 1
        let generation = generation
        let ids = columnIDs(excluding: primaryVersionID)
        state = .loading

        do {
            var columnVerses: [[BibleVerse]] = []
            for id in ids {
                let catalog = try await library.bible(id).repositories.catalog
                columnVerses.append(try await catalog.verses(in: bookID, chapter: chapter))
            }
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            rows = Self.align(primary: primary, columns: columnVerses)
            state = .loaded
        } catch is CancellationError {
            guard generation == self.generation else { return }
            state = .idle
        } catch {
            guard generation == self.generation else { return }
            rows = Self.align(primary: primary, columns: [])
            state = .failed(String(localized: "Couldn’t load a version to compare. \(String(describing: error))"))
        }
    }

    /// Rows for every verse number in any version, in order.
    static func align(primary: [BibleVerse], columns: [[BibleVerse]]) -> [Row] {
        let all = [primary] + columns
        let byNumber = all.map { verses in
            Dictionary(verses.map { ($0.reference.verse, $0.text) }, uniquingKeysWith: { first, _ in first })
        }
        let numbers = Set(all.flatMap { $0.map(\.reference.verse) }).sorted()
        return numbers.map { number in
            Row(verse: number, texts: byNumber.map { $0[number] })
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(columns), forKey: Self.columnsKey)
    }
}
