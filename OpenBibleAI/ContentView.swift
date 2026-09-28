//
//  ContentView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 13-09-26.
//

import SwiftUI
import BibleDomain
import BibleAI

struct ContentView: View {
    let appModel: AppModel
    let studyAssistantModel: StudyAssistantModel
    
    private static let initialReferences: [BibleReference] = {
        (1...3).map { verse in
            do {
                return try BibleReference(
                    bookID: "GEN",
                    chapter: 1,
                    verse: verse
                )
            } catch {
                preconditionFailure(
                    "Invalid initial Bible reference: \(error)"
                )
            }
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
                    studyAssistantModel: studyAssistantModel,
                    references: Self.initialReferences
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
