import Foundation

/// Version packages checked into the repository (`Bibles/`), for tests that
/// need real scripture now that no Bible is bundled with the app.
nonisolated enum RepositoryBibles {
    static let kjv = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Bibles/kjv", isDirectory: true)

    static var kjvBooks: URL { kjv.appendingPathComponent("books.json") }
    static var kjvVerses: URL { kjv.appendingPathComponent("verses.json") }
    static var kjvEmbeddings: URL { kjv.appendingPathComponent("embeddings.bin") }
}
