//
//  ModelFileDownloading.swift
//  BibleAI
//

import Foundation

/// Downloads one file to a temporary location, reporting bytes written so far.
protocol ModelFileDownloading: Sendable {
    func download(
        _ url: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL
}

struct URLSessionModelFileDownloader: ModelFileDownloading {
    func download(
        _ url: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        let delegate = ProgressDelegate(progress: progress)
        let (location, response) = try await URLSession.shared.download(
            for: URLRequest(url: url),
            delegate: delegate
        )
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: location)
            throw URLError(.badServerResponse)
        }
        // The system may delete `location` once this returns; move it first.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-download-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: location, to: kept)
        return kept
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
        let progress: @Sendable (Int64) -> Void

        init(progress: @escaping @Sendable (Int64) -> Void) {
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            progress(totalBytesWritten)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {}
    }
}
