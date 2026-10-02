//
//  BibleVersionMenu.swift
//  OpenBibleAI
//

import BibleDomain
import SwiftUI

/// Reader toolbar menu: switch the reading version, or manage (download and
/// delete) versions.
struct BibleVersionMenu: View {
    let library: BibleLibraryModel
    let current: BibleVersion
    let switchVersion: (String) -> Void

    @State private var isManaging = false

    var body: some View {
        Menu {
            Picker(
                "Version",
                selection: Binding(get: { current.id }, set: { switchVersion($0) })
            ) {
                ForEach(library.installedVersions) { version in
                    Text("\(version.name) (\(version.abbreviation))").tag(version.id)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button {
                isManaging = true
            } label: {
                Label("Manage Bibles…", systemImage: "books.vertical")
            }
            .accessibilityIdentifier("manageBiblesButton")
        } label: {
            Label(current.abbreviation, systemImage: "book")
                .labelStyle(.titleAndIcon)
        }
        .help("Bible version")
        .accessibilityIdentifier("versionMenu")
        .sheet(isPresented: $isManaging) {
            ManageBiblesView(library: library)
        }
    }
}

/// Download more versions or delete ones you no longer need.
struct ManageBiblesView: View {
    let library: BibleLibraryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BibleVersionList(library: library, allowsDelete: true)
                .navigationTitle("Bibles")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("manageBiblesDoneButton")
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
        .task { await library.refresh() }
    }
}
