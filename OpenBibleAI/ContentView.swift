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
    let aiEngine: AIEngineModel
    let semanticSearch: SemanticSearchModel
    let readingPositionStore: ReadingPositionStore
    let compare: BibleCompareModel

    @Environment(\.scenePhase) private var scenePhase

    /// Tabs and stacks on iPhone and iPad; kept across version switches.
    @State private var appNavigation = AppNavigation()

    #if os(visionOS)
    @State private var isShowingSettings = false
    #endif

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

            case .needsVersion:
                BibleOnboardingView(library: appModel.library) {
                    Task { await appModel.start() }
                }

            case let .ready(session):
                BibleReaderView(
                    aiEngine: aiEngine,
                    chatModel: session.chat,
                    semanticSearch: semanticSearch,
                    catalogModel: session.catalog,
                    searchModel: session.referenceSearch,
                    textSearchModel: session.textSearch,
                    readingPositionStore: readingPositionStore,
                    library: appModel.library,
                    compare: compare,
                    version: session.version,
                    switchVersion: { id in Task { await appModel.switchVersion(to: id) } },
                    appNavigation: appNavigation
                )
                // A new version gets fresh reader state; the saved book and
                // chapter are restored from the position store.
                .id(session.version.id)

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
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 480)
        #endif
        .task {
            #if DEBUG
            await UITestBibles.preinstall(into: appModel.library)
            #endif
            await appModel.start()
        }
        .task(id: appModel.session?.version.id) {
            semanticSearch.useIndex(appModel.session?.embeddingsURL)
        }
        .task {
            await aiEngine.refresh()
            await semanticSearch.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Apple Intelligence may have been turned on, or a model
                // finished preparing, while the app was in the background.
                Task {
                    await aiEngine.refresh()
                    await semanticSearch.refresh()
                }
            case .background:
                aiEngine.unloadModel()
                semanticSearch.unload()
            default:
                break
            }
        }
        #if os(visionOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("AI Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                AISettingsView(engine: aiEngine, semanticSearch: semanticSearch)
                    .navigationTitle("AI Settings")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                isShowingSettings = false
                            }
                        }
                    }
            }
        }
        #endif
    }
}
