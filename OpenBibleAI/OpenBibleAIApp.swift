//
//  OpenBibleAIApp.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 13-09-26.
//

import SwiftUI
import BibleAI
import BibleData
import BibleDomain

@main
struct OpenBibleAIApp: App {
    @State private var appModel: AppModel
    @State private var studyAssistantModel: StudyAssistantModel

    @MainActor
    init() {
        let appModel = AppModel(
            loadRepository: {
                guard let fileURL = Bundle.main.url(
                    forResource: "sample-bible",
                    withExtension: "json"
                ) else {
                    throw LaunchError.missingBibleResource
                }

                let repository =
                    try await JSONBibleRepository.load(
                        from: fileURL
                    )

                return CachingBibleRepository(
                    base: repository
                )
            }
        )

        let provider = OllamaProvider(
            model: "qwen3.8:latest"
        )

        let assistantModel = StudyAssistantModel(
            provider: provider
        )

        _appModel = State(initialValue: appModel)
        _studyAssistantModel = State(
            initialValue: assistantModel
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appModel: appModel,
                studyAssistantModel: studyAssistantModel
            )
        }
    }
}

private enum LaunchError: Error, Sendable {
    case missingBibleResource
}
