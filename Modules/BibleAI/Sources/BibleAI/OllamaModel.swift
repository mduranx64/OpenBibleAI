//
//  OllamaModel.swift
//  BibleAI
//
//  Created by Miguel Duran on 29-09-26.
//

public struct OllamaModel:
    Identifiable,
    Hashable,
    Sendable
{
    public var id: String {
        name
    }

    public let name: String
    public let size: Int64
    public let parameterSize: String?
    public let quantizationLevel: String?

    public init(
        name: String,
        size: Int64,
        parameterSize: String?,
        quantizationLevel: String?
    ) {
        self.name = name
        self.size = size
        self.parameterSize = parameterSize
        self.quantizationLevel = quantizationLevel
    }
}
