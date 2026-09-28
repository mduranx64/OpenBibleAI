//
//  OpenBibleAIApp.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 13-09-26.
//

import SwiftUI
import BibleData
import BibleDomain

@main
struct OpenBibleAIApp: App {
    @State private var appModel: AppModel

    @MainActor
    init() {
        let model = AppModel(
            loadRepository: {
                guard let fileURL = Bundle.main.url(
                    forResource: "sample-bible",
                    withExtension: "json"
                ) else {
                    throw LaunchError
                        .missingBibleResource
                }

                let jsonRepository =
                    try await JSONBibleRepository.load(
                        from: fileURL
                    )

                return CachingBibleRepository(
                    base: jsonRepository
                )
            }
        )

        _appModel = State(
            initialValue: model
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
        }
    }
}

private enum LaunchError: Error, Sendable {
    case missingBibleResource
}
