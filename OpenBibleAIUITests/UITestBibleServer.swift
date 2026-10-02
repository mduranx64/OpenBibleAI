import CryptoKit
import Foundation
import Network

/// Serves the repository's Bible version packages (`Bibles/<id>/<file>`) on
/// 127.0.0.1 so UI tests install Bibles through the app's real download path
/// without the internet. The app reads the server URL and the catalog (file
/// sizes and SHA-256) from its launch environment (see `UITestBibles`).
final class UITestBibleServer: @unchecked Sendable {
    static let shared = UITestBibleServer()

    /// Version packages offered to the app, in catalog order: the KJV, and
    /// `test-es`, test data made here from the KJV text with the Spanish book
    /// names (to check switching versions without another real package).
    static let versionIDs = ["kjv", "test-es"]

    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let biblesDirectory = repository.appendingPathComponent("Bibles", isDirectory: true)

    private lazy var testDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("UITestBibles-\(UUID().uuidString)", isDirectory: true)

    private func directory(for id: String) -> URL {
        id == "kjv" ? Self.biblesDirectory.appendingPathComponent(id) : testDirectory.appendingPathComponent(id)
    }

    /// Writes the `test-es` package: KJV verses and index, Spanish book names.
    private func makeTestPackage() throws {
        let kjv = Self.biblesDirectory.appendingPathComponent("kjv")
        let directory = directory(for: "test-es")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["verses.json", "embeddings.bin"] where !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            try FileManager.default.copyItem(at: kjv.appendingPathComponent(name), to: directory.appendingPathComponent(name))
        }
        let version: [String: Any] = [
            "id": "test-es", "name": "UI Test (Spanish book names)", "abbreviation": "TES",
            "language": "es", "copyright": "Test data",
        ]
        try JSONSerialization.data(withJSONObject: version).write(to: directory.appendingPathComponent("version.json"))

        let names = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.repository.appendingPathComponent("Tools/BibleImport/books/es.json"))
        ) as? [String: String] ?? [:]
        let books = try JSONSerialization.jsonObject(with: Data(contentsOf: kjv.appendingPathComponent("books.json"))) as? [[String: Any]] ?? []
        let renamed = books.map { book -> [String: Any] in
            var book = book
            if let id = book["book_id"] as? String, let name = names[id] { book["name"] = name }
            return book
        }
        try JSONSerialization.data(withJSONObject: renamed).write(to: directory.appendingPathComponent("books.json"))
    }

    private static let files = ["version.json", "books.json", "verses.json", "embeddings.bin"]

    private let queue = DispatchQueue(label: "UITestBibleServer")
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var catalogJSON: String?

    /// Launch environment for the app: server URL and catalog.
    func environment() throws -> [String: String] {
        let port = try start()
        return [
            "OPENBIBLE_UITEST_BIBLES_URL": "http://127.0.0.1:\(port.rawValue)",
            "OPENBIBLE_UITEST_CATALOG": try catalog(),
        ]
    }

    private func catalog() throws -> String {
        if let catalogJSON { return catalogJSON }
        try makeTestPackage()
        var entries: [[String: Any]] = []
        for id in Self.versionIDs {
            let directory = directory(for: id)
            let version = try JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("version.json"))
            )
            let files = try Self.files.map { name -> [String: Any] in
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return ["name": name, "size": data.count, "sha256": sha]
            }
            entries.append(["version": version, "files": files])
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: entries), as: UTF8.self)
        catalogJSON = json
        return json
    }

    private func start() throws -> NWEndpoint.Port {
        if let port { return port }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        let lastState = LockedState()
        listener.stateUpdateHandler = { state in
            lastState.value = "\(state)"
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
            listener.cancel()
            throw ServerError.notListening(lastState.value)
        }
        self.listener = listener
        self.port = port
        return port
    }

    enum ServerError: Error {
        case notListening(String)
    }

    private final class LockedState: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = "setup"
        var value: String {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(to: buffer[..<end.lowerBound], on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: Data, on connection: NWConnection) {
        let requestLine = String(decoding: head, as: UTF8.self).split(separator: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let path = parts.count >= 2 ? String(parts[1]) : ""
        let components = path.split(separator: "/").map(String.init)

        let response: Data
        if parts.first == "GET", components.count == 2,
           Self.versionIDs.contains(components[0]), Self.files.contains(components[1]),
           let body = try? Data(contentsOf: directory(for: components[0]).appendingPathComponent(components[1])) {
            response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n".utf8) + body
        } else {
            response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
