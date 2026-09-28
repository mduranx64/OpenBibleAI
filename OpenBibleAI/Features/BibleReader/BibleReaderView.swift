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
    let reference: BibleReference

    var body: some View {
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
        .task {
            guard case .idle = model.state else {
                return
            }

            await model.load(reference: reference)
        }
    }
}
