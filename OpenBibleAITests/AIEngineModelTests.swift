import BibleAI
import Foundation
import Testing

@testable import OpenBibleAI

@MainActor
struct AIEngineModelTests {
    private func model(
        apple: AppleModelStatus,
        tier: MLXModelTier?,
        store: FakeModelStore? = FakeModelStore()
    ) -> AIEngineModel {
        AIEngineModel(
            appleStatus: { apple },
            tier: tier,
            isSupportedHardware: tier != nil,
            store: tier == nil ? nil : store
        )
    }

    @Test
    func refreshPrefersAppleAndBuildsTheAppleProvider() async throws {
        let engine = model(apple: .available, tier: .standard)
        await engine.refresh()

        #expect(engine.choice == .apple)
        #expect(try engine.makeProvider() is AppleFoundationModelProvider)
        #expect(engine.contextCharacterLimit == BibleStudyContext.defaultCharacterLimit)
    }

    @Test
    func missingModelOffersDownloadAndCannotAnswerYet() async throws {
        let engine = model(apple: .unavailable(.deviceNotEligible), tier: .compact)
        await engine.refresh()

        #expect(engine.choice == .needsDownload(.compact))
        #expect(throws: AIEngineError.modelUnavailable) { try engine.makeProvider() }
    }

    @Test
    func downloadReportsProgressThenSwitchesToTheDownloadedModel() async throws {
        let store = FakeModelStore()
        let engine = model(apple: .unavailable(.deviceNotEligible), tier: .compact, store: store)
        await engine.refresh()

        await engine.startDownload().value

        #expect(engine.downloadState == .idle)
        #expect(engine.choice == .mlx(.compact))
        #expect(store.progressReported)
        #expect(try engine.makeProvider() is MLXModelProvider)
        #expect(engine.contextCharacterLimit == MLXModelTier.compact.contextCharacterLimit)
    }

    @Test
    func failedDownloadShowsAMessageAndStillOffersDownload() async throws {
        let store = FakeModelStore(failure: LocalModelStore.StoreError.checksumMismatch("model.safetensors"))
        let engine = model(apple: .unavailable(.deviceNotEligible), tier: .standard, store: store)
        await engine.refresh()

        await engine.startDownload().value

        guard case let .failed(message) = engine.downloadState else {
            Issue.record("Expected a failed download state, got \(engine.downloadState)")
            return
        }
        #expect(!message.isEmpty)
        #expect(engine.choice == .needsDownload(.standard))
    }

    @Test
    func deleteRemovesTheModelAndOffersDownloadAgain() async throws {
        let store = FakeModelStore(installed: true)
        let engine = model(apple: .unavailable(.deviceNotEligible), tier: .standard, store: store)
        await engine.refresh()
        #expect(engine.choice == .mlx(.standard))

        await engine.deleteModel()

        #expect(engine.choice == .needsDownload(.standard))
        #expect(store.deleted)
    }

    @Test
    func downloadedModelIsListedAndDeletableWhileAppleIsInUse() async throws {
        let store = FakeModelStore(installed: true)
        let engine = model(apple: .available, tier: .standard, store: store)
        await engine.refresh()
        #expect(engine.choice == .apple)
        #expect(engine.installedTiers == [.standard])

        await engine.deleteModel(.standard)

        #expect(store.deleted)
        #expect(engine.installedTiers.isEmpty)
        #expect(engine.choice == .apple)
    }

    @Test
    func otherTierLeftoverIsListedAndDeletedWithoutTouchingTheDevicesModel() async throws {
        let own = FakeModelStore(installed: true)
        let leftover = FakeModelStore(installed: true)
        let engine = AIEngineModel(
            appleStatus: { .unavailable(.deviceNotEligible) },
            tier: .standard,
            isSupportedHardware: true,
            store: own,
            otherStores: [.compact: leftover]
        )
        await engine.refresh()
        #expect(engine.installedTiers == [.standard, .compact])

        await engine.deleteModel(.compact)

        #expect(leftover.deleted)
        #expect(!own.deleted)
        #expect(engine.installedTiers == [.standard])
        #expect(engine.choice == .mlx(.standard))
    }

    @Test
    func unsupportedDevicesExplainInsteadOfOfferingDownload() async throws {
        let engine = model(apple: .unavailable(.unsupportedSystem), tier: nil)
        await engine.refresh()

        #expect(engine.choice == .unavailable(.unsupportedDevice))
        #expect(!engine.statusMessage.isEmpty)
    }
}

private final class FakeModelStore: LocalModelStoring, @unchecked Sendable {
    let directory = URL(fileURLWithPath: "/tmp/fake-model")
    private let lock = NSLock()
    private var installed: Bool
    private let failure: (any Error)?
    private var _progressReported = false
    private var _deleted = false

    init(installed: Bool = false, failure: (any Error)? = nil) {
        self.installed = installed
        self.failure = failure
    }

    var progressReported: Bool { lock.withLock { _progressReported } }
    var deleted: Bool { lock.withLock { _deleted } }

    func isInstalled() async -> Bool { lock.withLock { installed } }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        lock.withLock { _progressReported = true }
        if let failure { throw failure }
        progress(1)
        lock.withLock { installed = true }
    }

    func delete() async throws {
        lock.withLock {
            installed = false
            _deleted = true
        }
    }
}
