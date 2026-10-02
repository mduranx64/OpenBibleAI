import BibleDomain
import Foundation

/// A saved Bible chat. Plain `Codable` values: citations are stored as the
/// answer text and re-checked when a chat is opened, so no string indexes or
/// derived state are persisted.
nonisolated struct ChatConversation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String = "", createdAt: Date = .now, messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = messages
    }

    var summary: ChatSummary {
        ChatSummary(id: id, title: title, updatedAt: updatedAt)
    }
}

/// What the chat list shows for a saved conversation.
nonisolated struct ChatSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let updatedAt: Date
}

nonisolated struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    enum Status: Codable, Equatable, Sendable {
        case completed
        /// The user pressed Stop; the partial answer is kept.
        case stopped
        case failed(String)
    }

    let id: UUID
    let role: Role
    var text: String
    /// The verse attached to a question (user messages only).
    var attachedVerse: ChatVerseRange?
    /// Passages the answer was given (assistant messages only).
    var sources: [ChatVerseRange]
    var usedSemanticSearch: Bool
    var status: Status

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        attachedVerse: ChatVerseRange? = nil,
        sources: [ChatVerseRange] = [],
        usedSemanticSearch: Bool = false,
        status: Status = .completed
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachedVerse = attachedVerse
        self.sources = sources
        self.usedSemanticSearch = usedSemanticSearch
        self.status = status
    }
}

/// Verses `firstVerse...lastVerse` of one chapter, with a display title
/// ("Luke 2:4–7"). Stored instead of `BibleReference`, which isn't Codable.
nonisolated struct ChatVerseRange: Codable, Equatable, Hashable, Identifiable, Sendable {
    let bookID: String
    let chapter: Int
    let firstVerse: Int
    let lastVerse: Int
    let title: String

    var id: String { "\(bookID) \(chapter):\(firstVerse)-\(lastVerse)" }

    init(bookID: String, chapter: Int, firstVerse: Int, lastVerse: Int, bookName: String) {
        self.bookID = bookID
        self.chapter = chapter
        self.firstVerse = firstVerse
        self.lastVerse = max(firstVerse, lastVerse)
        let verses = firstVerse == self.lastVerse ? "\(firstVerse)" : "\(firstVerse)–\(self.lastVerse)"
        self.title = "\(bookName) \(chapter):\(verses)"
    }

    /// The first verse, which a tap opens.
    var reference: BibleReference? {
        try? BibleReference(bookID: bookID, chapter: chapter, verse: firstVerse)
    }

    var references: [BibleReference] {
        (firstVerse...lastVerse).compactMap {
            try? BibleReference(bookID: bookID, chapter: chapter, verse: $0)
        }
    }
}
