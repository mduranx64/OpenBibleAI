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

        let provider = SimulatedAIProvider(
            chunks: [
                "This passage presents God ",
                "as the creator and introduces ",
                "the beginning of the biblical narrative."
            ],
            delay: .milliseconds(250)
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
