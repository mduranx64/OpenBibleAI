import BibleAI
import SwiftUI

/// Settings for on-device AI: which engine is used and the model download.
struct AISettingsView: View {
    let engine: AIEngineModel
    let semanticSearch: SemanticSearchModel

    var body: some View {
        Form {
            Section("AI Study") {
                Text(engine.statusMessage)
                    .accessibilityIdentifier("aiStatusMessage")
            }

            Section("Apple Intelligence") {
                Text(appleStatusText)
            }

            if let tier = engine.tier {
                Section("Downloadable model") {
                    LabeledContent("Model", value: tier.displayName)
                    LabeledContent("Download size", value: engine.downloadSizeText)
                    ModelDownloadControls(engine: engine)
                }
            }

            if semanticSearch.isOffered {
                Section("Semantic search") {
                    Text("Helps the Bible chat find passages by meaning and in other languages. Runs on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Download size", value: semanticSearch.downloadSizeText)
                    SemanticSearchControls(model: semanticSearch)
                }
            }

            if !engine.installedTiers.isEmpty || semanticSearch.isInstalled {
                Section("Downloaded models") {
                    ForEach(engine.installedTiers, id: \.self) { tier in
                        DownloadedModelRow(
                            name: tier.displayName,
                            size: ByteCountFormatter.string(fromByteCount: tier.manifest.totalBytes, countStyle: .file)
                        ) {
                            await engine.deleteModel(tier)
                        }
                    }
                    if semanticSearch.isInstalled {
                        DownloadedModelRow(name: String(localized: "Search model"), size: semanticSearch.downloadSizeText) {
                            await semanticSearch.deleteModel()
                        }
                    }
                }
            }

            Section {
                Text("Answers are generated on this device and may be wrong. Check important points against the text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
        .task {
            await engine.refresh()
            await semanticSearch.refresh()
        }
    }

    private var appleStatusText: LocalizedStringKey {
        switch engine.appleStatus {
        case .available:
            "Available and used for AI study."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turned off. Turn on Apple Intelligence in System Settings to use Apple’s model."
        case .unavailable(.modelNotReady):
            "Preparing its model. This can take a while after turning it on."
        case .unavailable(.deviceNotEligible):
            "Not supported on this device."
        case .unavailable(.unsupportedSystem):
            "Requires a newer system version (26 or later)."
        case .unavailable(.other):
            "Not available right now."
        }
    }
}

/// A downloaded model with its size and a confirmed Delete button.
private struct DownloadedModelRow: View {
    let name: String
    let size: String
    let delete: () async -> Void
    @State private var isConfirming = false

    var body: some View {
        LabeledContent {
            Button("Delete", role: .destructive) { isConfirming = true }
                .accessibilityIdentifier("deleteDownloadedModel-\(name)")
        } label: {
            Text(name)
            Text(size)
        }
        .confirmationDialog("Delete \(name)?", isPresented: $isConfirming) {
            Button("Delete \(name)", role: .destructive) {
                Task { await delete() }
            }
        } message: {
            Text("This frees \(size). You can download it again later.")
        }
    }
}

/// Download / progress / cancel / delete controls for the device's model.
struct ModelDownloadControls: View {
    let engine: AIEngineModel

    var body: some View {
        switch engine.downloadState {
        case let .downloading(fraction):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction) {
                    Text("Downloading… \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                }
                .accessibilityIdentifier("modelDownloadProgress")
                Button("Cancel Download") { engine.cancelDownload() }
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .foregroundStyle(.red)
                Button("Try Again") { engine.startDownload() }
            }

        case .idle:
            switch engine.choice {
            case .mlx:
                HStack {
                    Label("Downloaded", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Delete Model", role: .destructive) {
                        Task { await engine.deleteModel() }
                    }
                }
            case .needsDownload:
                Button("Download Model (\(engine.downloadSizeText))") {
                    engine.startDownload()
                }
                .accessibilityIdentifier("downloadModelButton")
            case .apple, .unavailable:
                EmptyView()
            }
        }
    }
}
