import BibleDomain
import Foundation
import SwiftUI

/// Links for citations in "Ask the Bible" answers: `openbible://verse/JOH/9/7`.
enum CitationLink {
    static let scheme = "openbible"

    static func url(for reference: BibleReference) -> URL? {
        URL(string: "\(scheme)://verse/\(reference.bookID)/\(reference.chapter)/\(reference.verse)")
    }

    static func reference(from url: URL) -> BibleReference? {
        guard url.scheme == scheme, url.host() == "verse" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, let chapter = Int(parts[1]), let verse = Int(parts[2]) else { return nil }
        return try? BibleReference(bookID: parts[0], chapter: chapter, verse: verse)
    }
}

/// Builds the displayed answer: grounded citations become links; citations of
/// real verses outside the retrieved passages are links marked in orange; and
/// citations that don't resolve are struck through, so none is mistaken for
/// checked Scripture.
enum CitationText {
    static func attributed(
        _ answer: String,
        citations: [BibleChatModel.ResolvedCitation]
    ) -> AttributedString {
        var text = AttributedString(answer)
        for citation in citations {
            guard let range = Range(citation.range, in: text) else { continue }
            let target = citation.items.first { $0.status != .notFound && $0.reference != nil }
            if let reference = target?.reference, let url = CitationLink.url(for: reference) {
                text[range].link = url
                if !citation.items.allSatisfy(\.isVerified) {
                    text[range].foregroundColor = .orange
                }
            } else {
                text[range].foregroundColor = .orange
                text[range].strikethroughStyle = .single
            }
        }
        return text
    }

    static func hasUnverified(_ citations: [BibleChatModel.ResolvedCitation]) -> Bool {
        citations.contains { citation in citation.items.contains { !$0.isVerified } }
    }
}
