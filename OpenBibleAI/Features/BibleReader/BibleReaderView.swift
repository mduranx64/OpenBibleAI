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
    let references: [BibleReference]

    @State private var selectedIndex: Int

    init(
        model: BibleReaderModel,
        references: [BibleReference]
    ) {
        precondition(!references.isEmpty)

        self.model = model
        self.references = references
        _selectedIndex = State(initialValue: 0)
    }

    private var selectedReference: BibleReference {
        references[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.state {
                case .idle, .loading:
                    ProgressView("Loading verse…")

                case let .loaded(verse):
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

                case let .failed(message):
                    VStack(spacing: 12) {
                        Text("Couldn’t load the verse")
                            .font(.headline)

                        Text(message)
                            .foregroundStyle(.secondary)

                        Button("Retry") {
                            Task {
                                await model.load(
                                    reference: selectedReference
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Previous") {
                    selectedIndex -= 1
                }
                .disabled(selectedIndex == 0)

                Spacer()

                Text("\(selectedIndex + 1) of \(references.count)")
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Next") {
                    selectedIndex += 1
                }
                .disabled(selectedIndex == references.count - 1)
            }
            .padding()
        }
        .task(id: selectedReference) {
            await model.load(reference: selectedReference)
        }
    }
}
