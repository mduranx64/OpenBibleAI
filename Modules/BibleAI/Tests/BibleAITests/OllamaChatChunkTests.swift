//
//  OllamaChatChunkTests.swift
//  BibleAI
//
//  Created by Miguel Duran on 28-09-26.
//

import Foundation
import Testing

@testable import BibleAI

@Suite
struct OllamaChatChunkTests {
    @Test
    func decodesPartialAssistantContent() throws {
        let json = """
        {
            "message": {
                "role": "assistant",
                "content": "God is "
            },
            "done": false
        }
        """

        let chunk = try JSONDecoder().decode(
            OllamaChatChunk.self,
            from: Data(json.utf8)
        )

        #expect(chunk.message.role == "assistant")
        #expect(chunk.message.content == "God is ")
        #expect(chunk.done == false)
    }

    @Test
    func decodesFinalChunk() throws {
        let json = """
        {
            "message": {
                "role": "assistant",
                "content": ""
            },
            "done": true,
            "done_reason": "stop"
        }
        """

        let chunk = try JSONDecoder().decode(
            OllamaChatChunk.self,
            from: Data(json.utf8)
        )

        #expect(chunk.message.content.isEmpty)
        #expect(chunk.done)
    }
}
