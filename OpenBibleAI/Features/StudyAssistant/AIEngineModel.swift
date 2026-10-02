import BibleAI
import Foundation
import Observation

/// Chooses the on-device engine (Apple Intelligence, else a downloaded MLX
/// model) and manages the model download. UI-facing, main-actor state.
@MainActor
@Observable
final class AIEngineModel {
    enum DownloadState: Equatable {
        case idle
        case downloading(Double)
        case failed(String)
    }

    private(set) var choice: AIEngineChoice = .unavailable(.unsupportedDevice)
    private(set) var appleStatus: AppleModelStatus = .unavailable(.unsupportedSystem)
    private(set) var downloadState: DownloadState = .idle
    /// Downloaded chat models on disk, whichever engine is in use (Apple's
    /// model may be active while a downloaded Qwen still takes space).
    private(set) var installedTiers: [MLXModelTier] = []
    let tier: MLXModelTier?

    @ObservationIgnored private let appleStatusProvider: @MainActor () -> AppleModelStatus
    @ObservationIgnored private let isSupportedHardware: Bool
    @ObservationIgnored private let store: (any LocalModelStoring)?
    /// Stores of the other tier, which this device doesn't use but may hold
    /// from an earlier download (e.g. after a memory-tier change or tests).
    @ObservationIgnored private let otherStores: [MLXModelTier: any LocalModelStoring]
    @ObservationIgnored private var engine: MLXModelEngine?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadGeneration = 0

    init(
        appleStatus: @escaping @MainActor () -> AppleModelStatus = { .current },
        tier: MLXModelTier?,
        isSupportedHardware: Bool = MLXModelTier.isSupportedHardware,
        store: (any LocalModelStoring)?,
        otherStores: [MLXModelTier: any LocalModelStoring] = [:]
    ) {
        self.appleStatusProvider = appleStatus
        self.tier = tier
        self.isSupportedHardware = isSupportedHardware
        self.store = store
        self.otherStores = otherStores.filter { $0.key != tier }
    }

    /// The app's engine: this device's tier, stored under Application Support.
    static func live() -> AIEngineModel {
        let tier = MLXModelTier.current
        guard MLXModelTier.isSupportedHardware else { return AIEngineModel(tier: nil, store: nil) }
        var stores: [MLXModelTier: any LocalModelStoring] = [:]
        for candidate in [MLXModelTier.standard, .compact] {
            stores[candidate] = LocalModelStore(
                manifest: candidate.manifest,
                directory: modelsDirectory.appendingPathComponent(candidate.rawValue, isDirectory: true)
            )
        }
        return AIEngineModel(tier: tier, store: tier.flatMap { stores[$0] }, otherStores: stores)
    }

    private static var modelsDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("OpenBibleAI", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - State

    func refresh() async {
        appleStatus = appleStatusProvider()
        let installed = await store?.isInstalled() ?? false
        var tiers: [MLXModelTier] = []
        for candidate in [MLXModelTier.standard, .compact] {
            let isInstalled = candidate == tier
                ? installed
                : await otherStores[candidate]?.isInstalled() ?? false
            if isInstalled { tiers.append(candidate) }
        }
        installedTiers = tiers
        choice = .choose(
            apple: appleStatus,
            mlxTier: tier,
            isSupportedHardware: isSupportedHardware,
            isMLXModelInstalled: installed
        )
    }

    /// A provider for the next question, or `AIEngineError.modelUnavailable`.
    func makeProvider() throws -> any AIProvider {
        switch choice {
        case .apple:
            return AppleFoundationModelProvider()
        case let .mlx(tier):
            guard let store else { throw AIEngineError.modelUnavailable }
            let engine = self.engine ?? MLXModelEngine(directory: store.directory)
            self.engine = engine
            return MLXModelProvider(engine: engine, maximumResponseTokens: tier.maximumResponseTokens)
        case .needsDownload, .unavailable:
            throw AIEngineError.modelUnavailable
        }
    }

    /// The same engine as `makeProvider()`, for prompts built elsewhere
    /// (the "Ask the Bible" pipeline).
    func makePromptStreamer() throws -> any AIPromptStreaming {
        guard let streamer = try makeProvider() as? any AIPromptStreaming else {
            throw AIEngineError.modelUnavailable
        }
        return streamer
    }

    /// Chapter-context bound for the engine in use (smaller for compact models).
    var contextCharacterLimit: Int {
        if case let .mlx(tier) = choice { return tier.contextCharacterLimit }
        return BibleStudyContext.defaultCharacterLimit
    }

    /// Frees the downloaded model's memory (e.g. when the app is backgrounded).
    func unloadModel() {
        guard let engine else { return }
        Task { await engine.unload() }
    }

    // MARK: - Download

    @discardableResult
    func startDownload() -> Task<Void, Never> {
        if let downloadTask { return downloadTask }
        guard let store else { return Task {} }

        downloadGeneration += 1
        let generation = downloadGeneration
        downloadState = .downloading(0)

        // Called off the main actor by the store; hops back to report.
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                self?.reportProgress(fraction, generation: generation)
            }
        }

        let task = Task { [weak self] in
            var outcome = DownloadState.idle
            do {
                try await store.download(progress: report)
            } catch is CancellationError {
                outcome = .idle
            } catch {
                outcome = .failed(Self.message(for: error))
            }
            guard let self, generation == self.downloadGeneration else { return }
            self.downloadState = outcome
            self.downloadTask = nil
            await self.refresh()
        }
        downloadTask = task
        return task
    }

    func cancelDownload() {
        downloadGeneration += 1
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
    }

    func deleteModel() async {
        cancelDownload()
        if let engine {
            await engine.unload()
            self.engine = nil
        }
        try? await store?.delete()
        await refresh()
    }

    /// Deletes a downloaded model of either tier; the device's own tier goes
    /// through `deleteModel()` so a loaded model is unloaded first.
    func deleteModel(_ tier: MLXModelTier) async {
        guard tier != self.tier else { return await deleteModel() }
        try? await otherStores[tier]?.delete()
        await refresh()
    }

    /// Late progress callbacks from an older or finished download are ignored.
    private func reportProgress(_ fraction: Double, generation: Int) {
        guard generation == downloadGeneration,
              case let .downloading(current) = downloadState,
              fraction >= current
        else { return }
        downloadState = .downloading(fraction)
    }

    // MARK: - Text

    var downloadSizeText: String {
        guard let tier else { return "" }
        return ByteCountFormatter.string(fromByteCount: tier.manifest.totalBytes, countStyle: .file)
    }

    var statusMessage: String {
        switch choice {
        case .apple:
            return "Using Apple Intelligence on this device."
        case let .mlx(tier):
            return "Using the downloaded \(tier.displayName) model on this device."
        case let .needsDownload(tier):
            var text = "Download the \(tier.displayName) model (\(downloadSizeText)) to study with AI. It runs entirely on this device."
            if appleStatus == .unavailable(.appleIntelligenceNotEnabled) {
                text += " Or turn on Apple Intelligence in Settings."
            }
            return text
        case .unavailable(.appleIntelligenceOff):
            return "Turn on Apple Intelligence in Settings to study with AI."
        case .unavailable(.appleModelPreparing):
            return "Apple Intelligence is still preparing its model. Try again later."
        case .unavailable(.notEnoughMemory):
            return "This device doesn’t have enough memory for on-device AI. Reading and search still work."
        case .unavailable(.unsupportedDevice):
            return "AI study isn’t available on this device. Reading and search still work."
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case let LocalModelStore.StoreError.insufficientSpace(required, available):
            let formatter = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return "Not enough free space: the model needs \(formatter(required)), \(formatter(available)) available."
        case LocalModelStore.StoreError.checksumMismatch:
            return "The download was damaged. Please try again."
        default:
            return "The download failed: \(error.localizedDescription)"
        }
    }
}
