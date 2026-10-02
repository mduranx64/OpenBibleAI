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
        VStack(spacing: 0) {
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
            .padding(32)

            BibleVersionList(library: library, suggested: library.suggestedVersionID())
                .frame(maxWidth: 560)

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
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await library.refresh() }
    }
}

/// The catalog grouped by language, each version with its size, notice, and
/// download / progress / installed state. Shared by onboarding and Settings.
struct BibleVersionList: View {
    let library: BibleLibraryModel
    var suggested: String? = nil
    /// Settings shows Delete for installed versions; onboarding doesn't.
    var allowsDelete = false

    var body: some View {
        List {
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
        .confirmationDialog("Delete \(entry.version.name)?", isPresented: $isConfirmingDelete) {
            Button("Delete \(entry.version.name)", role: .destructive) {
                Task { _ = await library.delete(entry.id) }
            }
            .accessibilityIdentifier("confirmDeleteBible-\(entry.id)")
        } message: {
            Text("You can download it again later.")
        }
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
            if isInstalled {
                if allowsDelete, entry.id != library.activeVersionID, library.installedIDs.count > 1 {
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
