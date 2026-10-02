//
//  ModelManifest.swift
//  BibleAI
//

import Foundation

/// A downloadable model pinned to one Hugging Face revision, with the size
/// and SHA-256 of every file the MLX loader needs.
public struct ModelManifest: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public let name: String
        public let size: Int64
        public let sha256: String
    }

    public let repository: String
    public let revision: String
    public let files: [File]

    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    func url(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.name)")!
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

extension MLXModelTier {
    public var manifest: ModelManifest {
        switch self {
        case .standard: .qwen3_1_7B
        case .compact: .qwen3_0_6B
        }
    }
}
