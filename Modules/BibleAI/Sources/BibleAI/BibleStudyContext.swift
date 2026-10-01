//
//  BibleStudyContext.swift
//  BibleAI
//

import BibleDomain

/// Chooses how much of a chapter accompanies a selected verse in a study
/// request. The prompt size is bounded by characters of verse text.
public enum BibleStudyContext {
    public static let defaultCharacterLimit = 6_000

    /// The whole chapter when it fits `characterLimit`; otherwise a
    /// contiguous run of verses around `selected`, grown alternately before
    /// and after it until neither neighbour fits. The selected verse is
    /// always included, even if it alone exceeds the limit. Verses from other
    /// chapters or books are ignored; a selected verse that is not present
    /// yields no context.
    public static func verses(
        in chapter: [BibleVerse],
        around selected: BibleReference,
        characterLimit: Int = defaultCharacterLimit
    ) -> [BibleVerse] {
        let ordered = chapter
            .filter {
                $0.reference.bookID == selected.bookID
                    && $0.reference.chapter == selected.chapter
            }
            .sorted { $0.reference.verse < $1.reference.verse }

        guard let index = ordered.firstIndex(where: {
            $0.reference == selected
        }) else {
            return []
        }

        var lower = index
        var upper = index
        var used = ordered[index].text.count
        var growBeforeNext = true

        while true {
            let canGrowBefore = lower > 0
                && used + ordered[lower - 1].text.count <= characterLimit
            let canGrowAfter = upper < ordered.count - 1
                && used + ordered[upper + 1].text.count <= characterLimit

            guard canGrowBefore || canGrowAfter else { break }

            if (growBeforeNext && canGrowBefore) || !canGrowAfter {
                lower -= 1
                used += ordered[lower].text.count
            } else {
                upper += 1
                used += ordered[upper].text.count
            }

            growBeforeNext.toggle()
        }

        return Array(ordered[lower...upper])
    }
}
