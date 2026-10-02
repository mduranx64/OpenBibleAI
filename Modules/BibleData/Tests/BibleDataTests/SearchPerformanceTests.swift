//
//  SearchPerformanceTests.swift
//  BibleData
//

import Darwin
import Foundation
import Testing
import BibleData
import BibleDomain

/// Baseline measurements for text search on the full bundled KJV.
///
/// Skipped unless `OPENBIBLE_BENCH=1`, so normal test runs stay fast. It
/// prints a table and asserts only that searches return results; timings are
/// evidence for docs/DEVELOPMENT.md, not pass/fail thresholds.
///
///     OPENBIBLE_BENCH=1 swift test -c release \
///         --package-path Modules/BibleData --filter SearchPerformance
struct SearchPerformanceTests {
    private static let enabled =
        ProcessInfo.processInfo.environment["OPENBIBLE_BENCH"] == "1"

    private static let warmUpRuns = 3
    private static let measuredRuns = 20

    private static let cases: [(label: String, query: String)] = [
        ("very common word", "the"),
        ("common word", "lord"),
        ("rare word", "leviathan"),
        ("no match", "zzzqxj"),
        ("multi-word AND", "love one another"),
        ("quoted phrase", "\"in the beginning\""),
        ("two letters", "be"),
        ("diacritic fold", "Élan")
    ]

    @Test(.enabled(if: SearchPerformanceTests.enabled))
    func baselineOnFullKJV() async throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BibleDataTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // BibleData
            .deletingLastPathComponent() // Modules
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Bibles/kjv")

        let memoryBeforeLoad = Self.footprintMB()

        let catalog = try await JSONBibleBookCatalog.load(
            from: resources.appendingPathComponent("books.json")
        )

        let loadClock = ContinuousClock()
        let loadStart = loadClock.now
        let repository = try await JSONBibleRepository.load(
            from: resources.appendingPathComponent("verses.json"),
            books: catalog.books
        )
        let loadMS = Self.milliseconds(loadClock.now - loadStart)
        let memoryAfterLoad = Self.footprintMB()

        // Time InMemoryBibleRepository.init alone (index-ordering sort
        // included) by rebuilding it from the already decoded verses.
        var allVerses: [BibleVerse] = []
        for book in catalog.books {
            for chapter in try await repository.chapters(in: book.bookID) {
                allVerses += try await repository.verses(
                    in: book.bookID,
                    chapter: chapter
                )
            }
        }
        let initStart = loadClock.now
        let rebuilt = InMemoryBibleRepository(
            verses: allVerses,
            books: catalog.books
        )
        let initMS = Self.milliseconds(loadClock.now - initStart)
        _ = rebuilt

        var rows: [String] = []
        for (label, raw) in Self.cases {
            let query = try BibleTextQuery(raw)
            var durations: [Double] = []
            var totalCount = 0

            for run in 0..<(Self.warmUpRuns + Self.measuredRuns) {
                let start = loadClock.now
                let result = try await repository.search(query, limit: 100)
                let elapsed = Self.milliseconds(loadClock.now - start)
                totalCount = result.totalCount
                if run >= Self.warmUpRuns { durations.append(elapsed) }
            }

            durations.sort()
            let median = durations[durations.count / 2]
            let p95 = durations[Int(Double(durations.count - 1) * 0.95)]
            rows.append(
                "\(label.padding(toLength: 18, withPad: " ", startingAt: 0))"
                + "\(raw.padding(toLength: 22, withPad: " ", startingAt: 0))"
                + "matches \(String(totalCount).padding(toLength: 6, withPad: " ", startingAt: 0))"
                + "median \(Self.format(median)) ms   p95 \(Self.format(p95)) ms"
            )
        }

        // Ranked passage search: first call builds the BM25 index.
        let rankedBuildStart = loadClock.now
        _ = try await repository.rankedVerses(matching: ["jesus", "born", "bethlehem"], limit: 20)
        let rankedBuildMS = Self.milliseconds(loadClock.now - rankedBuildStart)
        var rankedDurations: [Double] = []
        for _ in 0..<Self.measuredRuns {
            let start = loadClock.now
            let ranked = try await repository.rankedVerses(
                matching: ["jesus", "blind", "sight", "eyes", "opened", "healed"], limit: 20
            )
            _ = try await repository.passages(
                around: ranked.map(\.reference), window: 2, limit: 6, characterBudget: 6_000
            )
            rankedDurations.append(Self.milliseconds(loadClock.now - start))
        }
        rankedDurations.sort()
        rows.append(
            "ranked passages: index build (first call) \(Self.format(rankedBuildMS)) ms, "
            + "query+passages median \(Self.format(rankedDurations[rankedDurations.count / 2])) ms"
        )

        let memoryAfterSearches = Self.footprintMB()

        // A second full round: footprint that only plateaus (allocator
        // high-water mark) is expected; continued growth would be a leak.
        for (_, raw) in Self.cases {
            let query = try BibleTextQuery(raw)
            for _ in 0..<Self.measuredRuns {
                _ = try await repository.search(query, limit: 100)
            }
        }
        let memoryAfterSecondRound = Self.footprintMB()

        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif

        print("""

        === OPENBIBLE SEARCH BASELINE (\(configuration)) ===
        \(ProcessInfo.processInfo.operatingSystemVersionString), \
        \(ProcessInfo.processInfo.processorCount) cores
        verses: \(allVerses.count), runs: \(Self.measuredRuns) after \(Self.warmUpRuns) warm-up
        JSONBibleRepository.load (decode + init): \(Self.format(loadMS)) ms
        InMemoryBibleRepository.init alone:       \(Self.format(initMS)) ms
        footprint MB: before load \(Self.format(memoryBeforeLoad)), \
        after load \(Self.format(memoryAfterLoad)), \
        after searches \(Self.format(memoryAfterSearches)), \
        after second round \(Self.format(memoryAfterSecondRound))
        \(rows.joined(separator: "\n"))
        === END BASELINE ===

        """)

        #expect(allVerses.count == 31_102)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }
}
