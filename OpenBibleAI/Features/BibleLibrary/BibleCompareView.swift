//
//  BibleCompareView.swift
//  OpenBibleAI
//

import BibleDomain
import SwiftUI

/// The chapter in the reading version and the compared versions, in aligned
/// columns (one row per verse number). Selecting a row selects the verse in
/// the reading version, as in the normal reading view.
struct BibleCompareView: View {
    let model: BibleCompareModel
    let library: BibleLibraryModel
    let primary: BibleVersion
    /// Location heading, e.g. "John 3".
    let title: String
    let bookID: String
    let chapter: Int
    let verses: [BibleVerse]
    let selectedReference: BibleReference?
    let selectionRevision: Int
    let selectVerse: (BibleReference) -> Void

    @State private var visibleVerse: Int?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private static let numberWidth: CGFloat = 32
    private static let minimumColumnWidth: CGFloat = 220

    private struct LoadKey: Equatable {
        let bookID: String
        let chapter: Int
        let primaryVersionID: String
        let columns: [String]
        let verseCount: Int
    }

    private var columns: [String] { model.columnIDs(excluding: primary.id) }

    var body: some View {
        layout
            .task(id: LoadKey(bookID: bookID, chapter: chapter, primaryVersionID: primary.id, columns: columns, verseCount: verses.count)) {
                await model.load(bookID: bookID, chapter: chapter, primary: verses, primaryVersionID: primary.id)
                scrollToSelection()
            }
            .onChange(of: selectionRevision) { _, _ in scrollToSelection() }
            .accessibilityIdentifier("compareView")
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            stacked
        } else {
            columnsLayout
        }
        #else
        columnsLayout
        #endif
    }

    private var columnsLayout: some View {
        GeometryReader { geometry in
            let count = CGFloat(columns.count + 1)
            let available = geometry.size.width - Self.numberWidth - 48
            let columnWidth = max(Self.minimumColumnWidth, available / count)

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    Text(title)
                        .font(.title.bold())
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("chapterTitle")

                    Section {
                        ForEach(model.rows) { row in
                            rowView(row, columnWidth: columnWidth)
                                .id(row.verse)
                        }
                    } header: {
                        header(columnWidth: columnWidth)
                    }

                    if case let .failed(message) = model.state {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .scrollTargetLayout()
                .padding(24)
            }
            .scrollPosition(id: $visibleVerse, anchor: .center)
        }
    }

    /// Narrow screens (iPhone): each verse lists the versions one under the
    /// other instead of side-by-side columns that would need sideways
    /// scrolling. Versions are added and removed from the Compare menu.
    private var stacked: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title.bold())
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("chapterTitle")

                ForEach(model.rows) { row in
                    stackedRow(row)
                        .id(row.verse)
                }

                if case let .failed(message) = model.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .scrollTargetLayout()
            .padding()
        }
        .scrollPosition(id: $visibleVerse, anchor: .center)
    }

    private func abbreviation(at index: Int) -> String {
        guard index > 0 else { return primary.abbreviation }
        // Rows can lag a column change until the next load.
        guard columns.indices.contains(index - 1) else { return "" }
        let id = columns[index - 1]
        return library.entry(id)?.version.abbreviation ?? id
    }

    private func stackedRow(_ row: BibleCompareModel.Row) -> some View {
        let reference = try? BibleReference(bookID: bookID, chapter: chapter, verse: row.verse)
        let isSelected = reference != nil && reference == selectedReference
        return Button {
            if let reference, row.texts.first ?? nil != nil { selectVerse(reference) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(row.verse)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(row.texts.enumerated()), id: \.offset) { index, text in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(abbreviation(at: index))
                                .font(.caption2.bold())
                                .foregroundStyle(index == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            Text(text ?? "—")
                                .foregroundStyle(text == nil ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .accessibilityIdentifier("compareCell-\(index)-\(row.verse)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("compareRow-\(row.verse)")
    }

    private func scrollToSelection() {
        guard let selectedReference, selectedReference.bookID == bookID, selectedReference.chapter == chapter else { return }
        visibleVerse = selectedReference.verse
    }

    // MARK: - Header

    private func header(columnWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear.frame(width: Self.numberWidth, height: 1)
            Text(primary.name)
                .font(.headline)
                .lineLimit(1)
                .frame(width: columnWidth, alignment: .leading)
            ForEach(columns, id: \.self) { id in
                columnHeader(id)
                    .frame(width: columnWidth, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func columnHeader(_ id: String) -> some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(library.installedVersions.filter { $0.id != primary.id && !columns.contains($0.id) }) { version in
                    Button(version.name) { model.replace(id, with: version.id) }
                }
            } label: {
                Text(library.entry(id)?.version.name ?? id)
                    .font(.headline)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                model.remove(id)
            } label: {
                Label("Remove \(library.entry(id)?.version.abbreviation ?? id)", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("removeCompareColumn-\(id)")
        }
    }

    // MARK: - Rows

    private func rowView(_ row: BibleCompareModel.Row, columnWidth: CGFloat) -> some View {
        let reference = try? BibleReference(bookID: bookID, chapter: chapter, verse: row.verse)
        let isSelected = reference != nil && reference == selectedReference
        return Button {
            if let reference, row.texts.first ?? nil != nil { selectVerse(reference) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(row.verse)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.numberWidth, alignment: .trailing)
                ForEach(Array(row.texts.enumerated()), id: \.offset) { index, text in
                    Text(text ?? "—")
                        .font(.body)
                        .foregroundStyle(text == nil ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .frame(width: columnWidth, alignment: .topLeading)
                        .accessibilityIdentifier("compareCell-\(index)-\(row.verse)")
                }
            }
            .padding(8)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("compareRow-\(row.verse)")
    }
}

/// Toolbar menu to add versions to compare, or stop comparing.
struct BibleCompareMenu: View {
    let model: BibleCompareModel
    let library: BibleLibraryModel
    let primary: BibleVersion

    var body: some View {
        let shown = model.columnIDs(excluding: primary.id)
        let candidates = library.installedVersions.filter { $0.id != primary.id && !shown.contains($0.id) }
        Menu {
            if candidates.isEmpty {
                Text("Download another version to compare.")
            }
            ForEach(candidates) { version in
                Button("\(version.name) (\(version.abbreviation))") { model.add(version.id) }
                    .disabled(!model.canAdd)
            }
            if !shown.isEmpty {
                Divider()
                Button("Stop Comparing") { model.closeAll() }
                    .accessibilityIdentifier("stopComparingButton")
            }
        } label: {
            Label("Compare", systemImage: "rectangle.split.3x1")
        }
        .help("Compare versions")
        .accessibilityIdentifier("compareMenu")
    }
}
