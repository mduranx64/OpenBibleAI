//
//  OllamaChatChunk.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

struct OllamaChatChunk: Decodable, Sendable {
    let message: Message
    let done: Bool
    let doneReason: String?

    struct Message: Decodable, Sendable {
        let role: String
        let content: String
        let thinking: String?
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case done
        case doneReason = "done_reason"
    }
}
