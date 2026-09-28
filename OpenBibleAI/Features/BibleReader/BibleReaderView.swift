//
//  BibleReaderView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import SwiftUI
import BibleDomain

struct BibleReaderView: View {
    let model: BibleReaderModel
    let studyAssistantModel: StudyAssistantModel
    let references: [BibleReference]

    @State private var selectedReference: BibleReference?

    init(
        model: BibleReaderModel,
        studyAssistantModel: StudyAssistantModel,
        references: [BibleReference]
    ) {
        precondition(!references.isEmpty)

        self.model = model
        self.studyAssistantModel = studyAssistantModel
        self.references = references

        _selectedReference = State(
            initialValue: references.first
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedReference) {
                ForEach(references, id: \.self) { reference in
                    Text("Verse \(reference.verse)")
                        .tag(reference)
                }
            }
            .navigationTitle("Genesis 1")
            .navigationSplitViewColumnWidth(
                min: 160,
                ideal: 200,
                max: 280
            )
        } content: {
            if let selectedReference {
                verseContent(for: selectedReference)
                    .task(id: selectedReference) {
                        await model.load(
                            reference: selectedReference
                        )
                    }
            } else {
                ContentUnavailableView(
                    "Select a Verse",
                    systemImage: "book.closed"
                )
            }
        } detail: {
            if let selectedReference,
               case let .loaded(verse) = model.state,
               verse.reference == selectedReference {
                StudyAssistantView(
                    model: studyAssistantModel,
                    verse: verse
                )
                .id(verse.reference)
                .navigationSplitViewColumnWidth(
                    min: 320,
                    ideal: 400
                )
            } else {
                ContentUnavailableView(
                    "AI Study Assistant",
                    systemImage: "sparkles",
                    description: Text(
                        "Select a verse to begin studying."
                    )
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func verseContent(
        for reference: BibleReference
    ) -> some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading verse…")

        case let .loaded(verse):
            if verse.reference == reference {
                VStack(alignment: .leading, spacing: 16) {
                    Text(
                        "\(verse.reference.bookID) " +
                        "\(verse.reference.chapter):" +
                        "\(verse.reference.verse)"
                    )
                    .font(.title2.bold())

                    Text(verse.text)
                        .font(.title3)
                        .textSelection(.enabled)
                }
                .frame(
                    maxWidth: 600,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .padding(32)
            } else {
                ProgressView("Loading verse…")
            }

        case let .failed(message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Couldn’t load the verse")
                    .font(.headline)

                Text(message)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task {
                        await model.load(reference: reference)
                    }
                }
            }
        }
    }
}
