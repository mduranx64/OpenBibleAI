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

    var body: some View {
        Group {
            switch appModel.state {
            case .idle, .loading:
                ProgressView("Loading Bible…")

            case .ready:
                VStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)

                    Text("Bible is ready")
                        .font(.title2)

                    Text("The local repository loaded successfully.")
                        .foregroundStyle(.secondary)
                }

            case let .failed(message):
                VStack(spacing: 12) {
                    Image(
                        systemName:
                            "exclamationmark.triangle"
                    )
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)

                    Text("Couldn’t load the Bible")
                        .font(.title2)

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
        .frame(
            minWidth: 640,
            minHeight: 480
        )
        .task {
            await appModel.start()
        }
    }
}

#Preview {
    ContentView(
        appModel: AppModel(
            loadRepository: {
                InMemoryBibleRepository(verses: [])
            }
        )
    )
}
