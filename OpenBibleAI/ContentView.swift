//
//  ContentView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 13-09-26.
//

import SwiftUI
import BibleDomain

struct ContentView: View {
    let appModel: AppModel

    private static let initialReference: BibleReference = {
        do {
            return try BibleReference(
                bookID: "GEN",
                chapter: 1,
                verse: 1
            )
        } catch {
            preconditionFailure(
                "Invalid initial Bible reference: \(error)"
            )
        }
    }()

    var body: some View {
        Group {
            switch appModel.state {
            case .idle, .loading:
                ProgressView("Loading Bible…")

            case let .ready(readerModel):
                BibleReaderView(
                    model: readerModel,
                    reference: Self.initialReference
                )

            case let .failed(message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)

                    Text("Couldn’t load the Bible")
                        .font(.headline)

                    Text(message)
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task {
                            await appModel.start()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            await appModel.start()
        }
    }
}
