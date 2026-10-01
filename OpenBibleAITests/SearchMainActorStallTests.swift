import BibleData
import BibleDomain
import Foundation
import Testing

@testable import OpenBibleAI

/// Measures whether a text search blocks the main actor.
///
/// A main-actor heartbeat ticks every millisecond while the real
/// `BibleTextSearchModel` searches the full bundled KJV. If the scan runs on
/// the main actor, the largest heartbeat gap approaches the search duration;
/// if it runs elsewhere, the gap stays at a few milliseconds.
///
/// Skipped unless `OPENBIBLE_BENCH=1` (forward it to the test host with
/// `TEST_RUNNER_OPENBIBLE_BENCH=1`). It prints evidence and asserts nothing
/// about timing.
@MainActor
struct SearchMainActorStallTests {
    private static let enabled =
        ProcessInfo.processInfo.environment["OPENBIBLE_BENCH"] == "1"

    @MainActor
    private final class Heartbeat {
        private(set) var largestGap: Duration = .zero
        private var task: Task<Void, Never>?

        func start() {
            task = Task { @MainActor in
                let clock = ContinuousClock()
                var last = clock.now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1))
                    let now = clock.now
                    largestGap = max(largestGap, now - last)
                    last = now
                }
            }
        }

        func resetGap() { largestGap = .zero }

        func stop() {
            task?.cancel()
            task = nil
        }
    }

    @Test(.enabled(if: SearchMainActorStallTests.enabled))
    func mainActorStallDuringSearch() async throws {
        let booksURL = try #require(
            Bundle.main.url(forResource: "kjv-books", withExtension: "json")
        )
        let versesURL = try #require(
            Bundle.main.url(forResource: "kjv-verses", withExtension: "json")
        )
        let catalog = try await JSONBibleBookCatalog.load(from: booksURL)
        let repository = try await JSONBibleRepository.load(
            from: versesURL,
            books: catalog.books
        )
        let model = BibleTextSearchModel(repository: repository)

        let heartbeat = Heartbeat()
        heartbeat.start()
        try await Task.sleep(for: .milliseconds(100))

        let clock = ContinuousClock()
        var rows: [String] = []
        for query in ["the", "leviathan", "love one another"] {
            for _ in 0..<5 {
                heartbeat.resetGap()
                let start = clock.now
                await model.search(query)
                let elapsed = clock.now - start
                // Yield so a heartbeat starved by the search can record its
                // gap; reading it earlier would show zero either way.
                try await Task.sleep(for: .milliseconds(20))
                rows.append(
                    "\(query.padding(toLength: 18, withPad: " ", startingAt: 0))"
                    + "search \(Self.ms(elapsed)) ms   largest main-actor gap \(Self.ms(heartbeat.largestGap)) ms"
                )
            }
        }
        heartbeat.stop()

        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif

        print("""

        === OPENBIBLE MAIN-ACTOR STALL (\(configuration)) ===
        \(rows.joined(separator: "\n"))
        === END STALL ===

        """)
    }

    private static func ms(_ duration: Duration) -> String {
        let parts = duration.components
        let value = Double(parts.seconds) * 1000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", value)
    }
}
