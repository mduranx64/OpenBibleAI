import Foundation
import OSLog

/// Saved Bible chats.
nonisolated protocol ChatStore: Sendable {
    /// Saved chats, most recently updated first.
    func summaries() async throws -> [ChatSummary]
    func load(_ id: UUID) async throws -> ChatConversation
    func save(_ conversation: ChatConversation) async throws
    func delete(_ id: UUID) async throws
}

/// One JSON file per chat under Application Support/OpenBibleAI/Chats.
/// Unreadable files (damaged, or written by a newer version) are skipped and
/// logged, never deleted, so a later version can still read them.
actor FileChatStore: ChatStore {
    nonisolated static let schemaVersion = 1

    nonisolated enum StoreError: Error, Equatable {
        case notFound(UUID)
        case unsupportedVersion(Int)
    }

    private nonisolated struct File: Codable {
        let schemaVersion: Int
        let conversation: ChatConversation
    }

    private nonisolated struct VersionOnly: Decodable {
        let schemaVersion: Int
    }

    let directory: URL
    private let logger = Logger(subsystem: "OpenBibleAI", category: "ChatStore")

    init(directory: URL) {
        self.directory = directory
    }

    static func live() -> FileChatStore {
        FileChatStore(
            directory: URL.applicationSupportDirectory
                .appendingPathComponent("OpenBibleAI/Chats", isDirectory: true)
        )
    }

    func summaries() async throws -> [ChatSummary] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }

        var result: [ChatSummary] = []
        for file in files where file.pathExtension == "json" {
            try Task.checkCancellation()
            do {
                result.append(try read(file).summary)
            } catch {
                logger.error("Skipping unreadable chat \(file.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(_ id: UUID) async throws -> ChatConversation {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { throw StoreError.notFound(id) }
        return try read(file)
    }

    func save(_ conversation: ChatConversation) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Default date encoding (seconds as a Double) round-trips exactly;
        // ISO 8601 would drop fractions and reorder chats saved in one second.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(File(schemaVersion: Self.schemaVersion, conversation: conversation))
        try data.write(to: url(for: conversation.id), options: .atomic)
    }

    func delete(_ id: UUID) async throws {
        do {
            try FileManager.default.removeItem(at: url(for: id))
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func read(_ file: URL) throws -> ChatConversation {
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionOnly.self, from: data).schemaVersion
        guard version <= Self.schemaVersion else { throw StoreError.unsupportedVersion(version) }
        return try decoder.decode(File.self, from: data).conversation
    }
}

/// In-memory chats for tests and previews.
actor InMemoryChatStore: ChatStore {
    private var conversations: [UUID: ChatConversation]
    private(set) var saveCount = 0

    init(_ conversations: [ChatConversation] = []) {
        self.conversations = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func summaries() async throws -> [ChatSummary] {
        conversations.values.map(\.summary).sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(_ id: UUID) async throws -> ChatConversation {
        guard let conversation = conversations[id] else { throw FileChatStore.StoreError.notFound(id) }
        return conversation
    }

    func save(_ conversation: ChatConversation) async throws {
        saveCount += 1
        conversations[conversation.id] = conversation
    }

    func delete(_ id: UUID) async throws {
        conversations[id] = nil
    }
}
