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

    #if !os(macOS)
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
                    switchVersion: { id in Task { await appModel.switchVersion(to: id) } }
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
        .frame(minWidth: 900, minHeight: 480)
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
        #if !os(macOS)
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
