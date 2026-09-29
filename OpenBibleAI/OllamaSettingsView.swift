//
//  OllamaSettingsView.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

import SwiftUI
import BibleAI

struct OllamaSettingsView: View {
    @Bindable var model: OllamaSettingsModel

    var body: some View {
        Form {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading Ollama models…")

            case .loaded:
                if model.models.isEmpty {
                    ContentUnavailableView(
                        "No Ollama Models",
                        systemImage: "shippingbox",
                        description: Text(
                            "Install a model with Ollama and refresh."
                        )
                    )
                } else {
                    Picker(
                        "Model",
                        selection: $model.selectedModelName
                    ) {
                        ForEach(model.models) { ollamaModel in
                            Text(ollamaModel.name)
                                .tag(Optional(ollamaModel.name))
                        }
                    }

                    Button("Refresh Models") {
                        Task {
                            await model.load()
                        }
                    }
                }

            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        "Couldn’t Load Models",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task {
                            await model.load()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 280)
        .task {
            await model.load()
        }
    }
}
