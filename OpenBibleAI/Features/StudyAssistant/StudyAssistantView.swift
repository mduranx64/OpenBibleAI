//
//  StudyAssistantView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import SwiftUI
import BibleAI
import BibleDomain

struct StudyAssistantView: View {
    let model: StudyAssistantModel
    let engine: AIEngineModel
    let verse: BibleVerse
    /// Full book name for display and prompts; nil falls back to the book ID.
    var bookName: String?
    /// The loaded chapter containing `verse`, used for bounded context.
    var chapterVerses: [BibleVerse] = []

    @State private var question = ""
    @State private var requestTask: Task<Void, Never>?
    @State private var hasAskedQuestion = false

    private var trimmedQuestion: String {
        question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var referenceLabel: String {
        let reference = verse.reference
        return "\(bookName ?? reference.bookID) \(reference.chapter):\(reference.verse)"
    }

    /// Generated state is shown only for the verse it was generated for.
    private var ownsCurrentAnswer: Bool {
        model.answerReference == verse.reference
    }

    private var answerText: String {
        model.answer(for: verse.reference)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Study Assistant")
                .font(.title2.bold())

            verseCard

            if engine.choice.isUsable {
                askContent
            } else {
                unavailableContent
            }
        }
        .padding()
        .onAppear {
            // A new verse starts clean; late chunks from another verse's
            // stream are dropped by the model's generation guard.
            model.reset()
        }
        .onDisappear {
            requestTask?.cancel()
        }
    }

    @ViewBuilder
    private var askContent: some View {
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
                } else if ownsCurrentAnswer {
                    Label(
                        "Generated explanation — not Scripture",
                        systemImage: "sparkles"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("generatedAnswerLabel")

                    if !answerText.isEmpty {
                        Text(answerText)
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

                    if model.state == .completed {
                        Text("AI-generated and may contain errors. Check important points against the text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    /// Why AI can't answer here, with the download offer where it helps.
    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(engine.statusMessage)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("aiUnavailableMessage")
            if engine.tier != nil {
                ModelDownloadControls(engine: engine)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Canonical text, visibly separate from the generated answer below.
    private var verseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(referenceLabel)
                .font(.headline)
                .accessibilityIdentifier("studyVerseReference")

            Text(verse.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
                bookName: bookName,
                chapterVerses: chapterVerses,
                question: submittedQuestion
            )
        }
    }
}
