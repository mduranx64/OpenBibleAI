import Foundation
import Testing

@testable import OpenBibleAI

struct FileChatStoreTests {
    private func temporaryStore() -> (FileChatStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (FileChatStore(directory: directory), directory)
    }

    private func conversation(_ title: String, updated: TimeInterval) -> ChatConversation {
        var conversation = ChatConversation(
            title: title,
            createdAt: Date(timeIntervalSince1970: 1_000),
            messages: [
                ChatMessage(
                    role: .user,
                    text: "What does this mean?",
                    attachedVerse: ChatVerseRange(bookID: "JHN", chapter: 3, firstVerse: 16, lastVerse: 16, bookName: "John")
                ),
                ChatMessage(
                    role: .assistant,
                    text: "God loved the world [John 3:16].",
                    sources: [ChatVerseRange(bookID: "JHN", chapter: 3, firstVerse: 14, lastVerse: 18, bookName: "John")],
                    usedSemanticSearch: true,
                    status: .failed("Oops")
                )
            ]
        )
        conversation.updatedAt = Date(timeIntervalSince1970: updated)
        return conversation
    }

    @Test
    func savedChatsRoundTripAndListNewestFirst() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try await store.summaries().isEmpty, "No folder yet means no chats")

        let older = conversation("Older", updated: 2_000)
        let newer = conversation("Newer", updated: 3_000.25)
        try await store.save(older)
        try await store.save(newer)

        #expect(try await store.load(older.id) == older)
        #expect(try await store.summaries().map(\.title) == ["Newer", "Older"])
    }

    @Test
    func deleteRemovesOnlyThatChat() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = conversation("Kept", updated: 2_000)
        let removed = conversation("Removed", updated: 3_000)
        try await store.save(kept)
        try await store.save(removed)

        try await store.delete(removed.id)
        try await store.delete(removed.id) // already gone: no error

        #expect(try await store.summaries().map(\.id) == [kept.id])
        await #expect(throws: FileChatStore.StoreError.notFound(removed.id)) { try await store.load(removed.id) }
    }

    @Test
    func damagedAndNewerVersionFilesAreSkippedButKept() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = conversation("Good", updated: 2_000)
        try await store.save(good)

        let damaged = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{ not json".utf8).write(to: damaged)
        let future = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data(#"{"schemaVersion": 99, "conversation": {}}"#.utf8).write(to: future)

        #expect(try await store.summaries().map(\.id) == [good.id])
        #expect(FileManager.default.fileExists(atPath: damaged.path))
        #expect(FileManager.default.fileExists(atPath: future.path))
    }
}
