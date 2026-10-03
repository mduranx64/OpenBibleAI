//
//  BibleOnboardingView.swift
//  OpenBibleAI
//

import BibleDomain
import SwiftUI

/// First launch: no Bible is installed yet. The user downloads one or more
/// versions (the one matching their language is suggested), then continues.
struct BibleOnboardingView: View {
    let library: BibleLibraryModel
    let continueReading: () -> Void

    var body: some View {
        #if os(iOS)
        // The heading scrolls with the list and Start Reading stays at the
        // bottom, so the versions keep room on short (landscape) screens.
        BibleVersionList(library: library, suggested: library.suggestedVersionID()) {
            heading
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .task { await library.refresh() }
        #else
        VStack(spacing: 0) {
            heading
                .padding(32)

            BibleVersionList(library: library, suggested: library.suggestedVersionID())
                .frame(maxWidth: 560)

            startButton
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await library.refresh() }
        #endif
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Choose a Bible")
                .font(.largeTitle.bold())
            Text("Download a version to start reading. You can add more versions later from the version menu.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var startButton: some View {
        Button {
            continueReading()
        } label: {
            Text("Start Reading")
                .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(library.installedIDs.isEmpty)
        .accessibilityIdentifier("onboardingContinueButton")
    }
}

extension BibleVersionList where Header == EmptyView {
    init(library: BibleLibraryModel, suggested: String? = nil, allowsDelete: Bool = false) {
        self.init(library: library, suggested: suggested, allowsDelete: allowsDelete) { EmptyView() }
    }
}

/// The catalog grouped by language, each version with its size, notice, and
/// download / progress / installed state. Shared by onboarding and Settings.
struct BibleVersionList<Header: View>: View {
    let library: BibleLibraryModel
    var suggested: String? = nil
    /// Settings shows Delete for installed versions; onboarding doesn't.
    var allowsDelete = false
    /// Scrolls with the list, above the versions (onboarding on iOS).
    @ViewBuilder var header: () -> Header

    var body: some View {
        List {
            if Header.self != EmptyView.self {
                Section {
                    header()
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(languageGroups, id: \.language) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        BibleVersionRow(
                            library: library,
                            entry: entry,
                            isSuggested: entry.id == suggested,
                            allowsDelete: allowsDelete
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("bibleVersionList")
    }

    private struct LanguageGroup {
        let language: String
        let title: String
        let entries: [BibleCatalogEntry]
    }

    /// Languages in catalog order, with the suggested version's language first.
    private var languageGroups: [LanguageGroup] {
        var order: [String] = []
        for entry in library.catalog where !order.contains(entry.version.languageCode) {
            order.append(entry.version.languageCode)
        }
        if let suggested = library.entry(suggested ?? "")?.version.languageCode,
           let index = order.firstIndex(of: suggested) {
            order.insert(order.remove(at: index), at: 0)
        }
        return order.map { language in
            LanguageGroup(
                language: language,
                title: Locale.current.localizedString(forIdentifier: language)?.localizedCapitalized ?? language,
                entries: library.catalog.filter { $0.version.languageCode == language }
            )
        }
    }
}

private struct BibleVersionRow: View {
    let library: BibleLibraryModel
    let entry: BibleCatalogEntry
    let isSuggested: Bool
    let allowsDelete: Bool
    @State private var isConfirmingDelete = false

    private var isInstalled: Bool { library.installedIDs.contains(entry.id) }

    private var canDelete: Bool {
        allowsDelete && isInstalled && entry.id != library.activeVersionID && library.installedIDs.count > 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.version.name)
                        .font(.headline)
                    if isSuggested, !isInstalled {
                        Text("Suggested")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                Text("\(entry.version.abbreviation) · \(ByteCountFormatter.string(fromByteCount: entry.downloadSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.version.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let update = library.availableUpdate(entry.id) {
                    Text("Update available · \(ByteCountFormatter.string(fromByteCount: update.downloadSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                if case let .failed(message) = library.downloads[entry.id] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("bibleDownloadError-\(entry.id)")
                }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bibleVersion-\(entry.id)")
        #if os(iOS)
        // On iOS, Delete is a swipe (or long-press) action, leaving room for
        // the name and notice on narrow screens. Swiping and tapping Delete
        // is the confirmation, as in Mail or Files (a dialog from a swiped
        // row doesn't present); the version can be downloaded again.
        .swipeActions(edge: .trailing) {
            if canDelete {
                deleteButton
                    .tint(.red)
            }
        }
        .contextMenu {
            if canDelete {
                deleteButton
            }
        }
        #endif
        .confirmationDialog("Delete \(entry.version.name)?", isPresented: $isConfirmingDelete) {
            Button("Delete \(entry.version.name)", role: .destructive) {
                Task { _ = await library.delete(entry.id) }
            }
            .accessibilityIdentifier("confirmDeleteBible-\(entry.id)")
        } message: {
            Text("You can download it again later.")
        }
    }

    private var deleteButton: some View {
        Button {
            Task { _ = await library.delete(entry.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("deleteBible-\(entry.id)")
    }

    /// Delete beside the state (Mac); on iOS it is a swipe action.
    private var showsDeleteButton: Bool {
        #if os(iOS)
        false
        #else
        canDelete
        #endif
    }

    @ViewBuilder
    private var trailing: some View {
        switch library.downloads[entry.id] {
        case let .downloading(fraction):
            HStack {
                ProgressView(value: fraction)
                    .frame(width: 80)
                    .accessibilityIdentifier("bibleDownloadProgress-\(entry.id)")
                Button {
                    library.cancel(entry.id)
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        case .failed:
            Button("Try Again") { library.install(entry.id) }
        case nil:
            if isInstalled, library.availableUpdate(entry.id) != nil {
                HStack {
                    Button("Update") { library.update(entry.id) }
                        .accessibilityIdentifier("updateBible-\(entry.id)")
                    if showsDeleteButton {
                        Button("Delete", role: .destructive) { isConfirmingDelete = true }
                            .accessibilityIdentifier("deleteBible-\(entry.id)")
                    }
                }
            } else if isInstalled {
                if showsDeleteButton {
                    Button("Delete", role: .destructive) { isConfirmingDelete = true }
                        .accessibilityIdentifier("deleteBible-\(entry.id)")
                } else {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("bibleInstalled-\(entry.id)")
                }
            } else {
                Button("Download") { library.install(entry.id) }
                    .accessibilityIdentifier("downloadBible-\(entry.id)")
            }
        }
    }
}
