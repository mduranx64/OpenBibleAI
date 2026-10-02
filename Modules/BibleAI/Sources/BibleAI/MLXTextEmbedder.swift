//
//  MLXTextEmbedder.swift
//  BibleAI
//

import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon

/// Embeds text with the downloaded multilingual embedding model (Qwen3
/// Embedding 0.6B) via MLX. Verse vectors (built once, offline) and question
/// vectors (on device) go through this same code, so they are comparable.
///
/// Last-token pooling, an explicit `<|endoftext|>` end token, truncation to
/// `dimensions` (Matryoshka) and L2 normalisation. Questions get the model's
/// instruction prefix; verses are embedded as plain text.
public actor MLXTextEmbedder {
    public static let defaultDimensions = 256
    public static let queryInstruction =
        "Given a question about the Bible, retrieve the Bible verses that answer it"
    /// Verses are short; this bounds memory for unusually long inputs.
    static let maximumTokens = 512

    public let dimensions: Int
    private let directory: URL
    private var container: EmbedderModelContainer?

    public init(directory: URL, dimensions: Int = MLXTextEmbedder.defaultDimensions) {
        self.directory = directory
        self.dimensions = dimensions
    }

    public func unload() {
        container = nil
    }

    public func embedQuery(_ question: String) async throws -> [Float] {
        let text = "Instruct: \(Self.queryInstruction)\nQuery:\(question)"
        return try await embed([text])[0]
    }

    public func embedDocuments(_ texts: [String]) async throws -> [[Float]] {
        try await embed(texts)
    }

    private func loaded() async throws -> EmbedderModelContainer {
        if let container { return container }
        let loaded = try await EmbedderModelFactory.shared.loadContainer(
            from: directory,
            using: TransformersTokenizerLoader()
        )
        container = loaded
        return loaded
    }

    private func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let container = try await loaded()
        let dimensions = self.dimensions

        return await container.perform { context in
            let tokenizer = context.tokenizer
            let endToken = tokenizer.convertTokenToId("<|endoftext|>") ?? tokenizer.eosTokenId ?? 0

            let tokenized = texts.map { text -> [Int] in
                var ids = Array(tokenizer.encode(text: text, addSpecialTokens: true).prefix(Self.maximumTokens - 1))
                if ids.last != endToken { ids.append(endToken) }
                return ids
            }
            let length = tokenized.map(\.count).max() ?? 1
            let padded = stacked(tokenized.map {
                MLXArray(($0 + Array(repeating: endToken, count: length - $0.count)).map(Int32.init))
            })
            let mask = stacked(tokenized.map {
                MLXArray(Array(repeating: Int32(1), count: $0.count) + Array(repeating: Int32(0), count: length - $0.count))
            })

            let output = context.model(padded, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
            let pooled = Pooling(strategy: .last)(output, mask: mask, normalize: false)
            pooled.eval()

            return (0..<texts.count).map { row in
                let vector = Array(pooled[row].asArray(Float.self).prefix(dimensions))
                let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
                return length > 0 ? vector.map { $0 / length } : vector
            }
        }
    }
}
