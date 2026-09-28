//
//  StudyAssistantView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import SwiftUI
import BibleDomain

struct StudyAssistantView: View {
    let model: StudyAssistantModel
    let verse: BibleVerse

    @State private var question = ""
    @State private var requestTask: Task<Void, Never>?
    @State private var hasAskedQuestion = false

    private var trimmedQuestion: String {
        question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Study Assistant")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !hasAskedQuestion {
                        ContentUnavailableView(
                            "Ask About This Verse",
                            systemImage: "sparkles",
                            description: Text(
                                "Enter a question to study the selected verse."
                            )
                        )
                    } else {
                        if !model.answer.isEmpty {
                            Text(model.answer)
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }

                        if model.state == .streaming {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if case let .failed(message) = model.state {
                            Text(message)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            TextField(
                "Ask a question about this verse",
                text: $question,
                axis: .vertical
            )
            .lineLimit(2...5)
            .disabled(model.state == .streaming)
            .onSubmit {
                startRequest()
            }

            HStack {
                Spacer()

                if model.state == .streaming {
                    Button("Stop") {
                        requestTask?.cancel()
                    }
                } else {
                    Button("Ask") {
                        startRequest()
                    }
                    .keyboardShortcut(.return)
                    .disabled(trimmedQuestion.isEmpty)
                }
            }
        }
        .padding()
        .onDisappear {
            requestTask?.cancel()
        }
    }

    private func startRequest() {
        guard !trimmedQuestion.isEmpty else {
            return
        }

        requestTask?.cancel()
        hasAskedQuestion = true

        let submittedQuestion = trimmedQuestion

        requestTask = Task {
            await model.ask(
                verse: verse,
                question: submittedQuestion
            )
        }
    }
}
