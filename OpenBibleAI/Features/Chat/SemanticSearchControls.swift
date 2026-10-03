import SwiftUI

/// Download / progress / cancel / delete for the optional search model.
struct SemanticSearchControls: View {
    let model: SemanticSearchModel

    var body: some View {
        switch model.downloadState {
        case let .downloading(fraction):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction) {
                    Text("Downloading search model… \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                }
                .accessibilityIdentifier("searchModelDownloadProgress")
                Button("Cancel Download") { model.cancelDownload() }
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).foregroundStyle(.red)
                Button("Try Again") { model.startDownload() }
            }

        case .idle:
            if model.isInstalled {
                HStack {
                    Label("Installed", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Delete Search Model", role: .destructive) {
                        Task { await model.deleteModel() }
                    }
                }
            } else {
                Button("Improve Search (\(model.downloadSizeText))") {
                    model.startDownload()
                }
                .accessibilityIdentifier("downloadSearchModelButton")
            }
        }
    }
}
