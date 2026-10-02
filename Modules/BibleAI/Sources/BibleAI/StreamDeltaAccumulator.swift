//
//  StreamDeltaAccumulator.swift
//  BibleAI
//

/// Turns cumulative snapshots ("God", "God so", …) into the deltas the
/// `AIProvider` contract yields (" so", …). Already-emitted text cannot be
/// retracted, so a snapshot that diverges emits only what follows the common
/// prefix.
struct StreamDeltaAccumulator: Sendable {
    private var emitted = ""

    mutating func delta(for snapshot: String) -> String {
        let common = emitted.commonPrefix(with: snapshot)
        let delta = String(snapshot.dropFirst(common.count))
        emitted = snapshot
        return delta
    }
}
