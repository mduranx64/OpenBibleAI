//
//  ModelManifest.swift
//  BibleAI
//

import Foundation

/// A download pinned to one revision, with the size and SHA-256 of every
/// file: a model on Hugging Face (`repository` at a commit) or assets of a
/// GitHub release, such as a Bible version package (`revision` names the
/// package, e.g. "kjv-1", and prefixes its assets in the shared release).
public struct ModelManifest: Equatable, Sendable, Codable {
    public struct File: Equatable, Sendable, Codable {
        public let name: String
        /// Size and SHA-256 of the installed file.
        public let size: Int64
        public let sha256: String
        /// When set, the file is downloaded compressed (raw DEFLATE, asset
        /// `<name>.zlib`) and decompressed on install.
        public let archive: Archive?

        public init(name: String, size: Int64, sha256: String, archive: Archive? = nil) {
            self.name = name
            self.size = size
            self.sha256 = sha256
            self.archive = archive
        }

        /// Bytes transferred to install the file.
        public var downloadSize: Int64 { archive?.size ?? size }
    }

    /// The compressed form of a file, as published.
    public struct Archive: Equatable, Sendable, Codable {
        public let size: Int64
        public let sha256: String

        public init(size: Int64, sha256: String) {
            self.size = size
            self.sha256 = sha256
        }
    }

    public enum Host: Equatable, Sendable, Codable {
        case huggingFace
        /// Assets `<revision>-<file>` of the release `tag` of `repository`.
        case gitHubRelease(tag: String)
        /// `<base>/<revision>/<file>`, e.g. a local server in UI tests.
        case baseURL(URL)
    }

    public let repository: String
    public let revision: String
    public let files: [File]
    public let host: Host

    public init(repository: String, revision: String, files: [File], host: Host = .huggingFace) {
        self.repository = repository
        self.revision = revision
        self.files = files
        self.host = host
    }

    /// Bytes on disk once installed.
    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// Bytes transferred to install (smaller when files are compressed).
    public var downloadBytes: Int64 {
        files.reduce(0) { $0 + $1.downloadSize }
    }

    public func url(for file: File) -> URL {
        let name = file.archive == nil ? file.name : "\(file.name).zlib"
        return switch host {
        case .huggingFace:
            URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(name)")!
        case let .gitHubRelease(tag):
            URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(revision)-\(name)")!
        case let .baseURL(base):
            base.appendingPathComponent(revision).appendingPathComponent(name)
        }
    }
}

extension ModelManifest {
    // Values recorded 2026-10-01 from the Hugging Face API (LFS files) and by
    // hashing the small files at the same revision. Apache-2.0 models.

    private static let sharedTokenizerFiles: [File] = [
        File(name: "added_tokens.json", size: 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"),
        File(name: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
        File(name: "special_tokens_map.json", size: 613, sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
        File(name: "tokenizer.json", size: 11_422_654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
        File(name: "tokenizer_config.json", size: 9_706, sha256: "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0"),
        File(name: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
    ]

    public static let qwen3_1_7B = ModelManifest(
        repository: "mlx-community/Qwen3-1.7B-4bit",
        revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
        files: [
            File(name: "config.json", size: 937, sha256: "507a6701220524eb8b283425bf0856a9ae4f21f4052e563896ddd668994b1dc7"),
            File(name: "model.safetensors", size: 968_080_210, sha256: "0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f"),
            File(name: "model.safetensors.index.json", size: 49_731, sha256: "1e3058d4ba4b04e4de35b74467725cbef90ff022198404218e48f21adc9cfa15"),
        ] + sharedTokenizerFiles
    )

    public static let qwen3_0_6B = ModelManifest(
        repository: "mlx-community/Qwen3-0.6B-4bit",
        revision: "73e3e38d981303bc594367cd910ea6eb48349da8",
        files: [
            File(name: "config.json", size: 937, sha256: "15d3ac26c043ae477273ed5802ee0f0b33bb14f18c9d3dd70910c02d906e3f1f"),
            File(name: "model.safetensors", size: 335_450_584, sha256: "392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2"),
            File(name: "model.safetensors.index.json", size: 49_731, sha256: "7b294141456f6904936db03c00bca50fb5f6198f652fe8483f9cd2a1018accfb"),
        ] + sharedTokenizerFiles
    )
}

extension ModelManifest {
    /// Multilingual embedding model for semantic verse search (optional download).
    /// Recorded 2026-10-01; Apache-2.0.
    public static let qwen3Embedding = ModelManifest(
        repository: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
        revision: "6c3ae70858513f1a78e9cdca3cae330d9075cd2a",
        files: [
            File(name: "added_tokens.json", size: 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"),
            File(name: "config.json", size: 937, sha256: "e7dfa5b73fb2a03cbc8fb40c394e95b99f03348e237f7f28e7a1daf56a2169bb"),
            File(name: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
            File(name: "model.safetensors", size: 335_296_756, sha256: "3d773d5ee582eda445daeee23f7a2b76124011796df244ddb45e22638fdb7cde"),
            File(name: "model.safetensors.index.json", size: 49_770, sha256: "90d82744cdb6b7d093f0b812fc21a49b6ffa9d0084a45428f0cfd01eb4adbe12"),
            File(name: "special_tokens_map.json", size: 613, sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
            File(name: "tokenizer.json", size: 11_423_705, sha256: "def76fb086971c7867b829c23a26261e38d9d74e02139253b38aeb9df8b4b50a"),
            File(name: "tokenizer_config.json", size: 5_404, sha256: "443bfa629eb16387a12edbf92a76f6a6f10b2af3b53d87ba1550adfcf45f7fa0"),
            File(name: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
        ]
    )
}

extension MLXModelTier {
    public var manifest: ModelManifest {
        switch self {
        case .standard: .qwen3_1_7B
        case .compact: .qwen3_0_6B
        }
    }
}
