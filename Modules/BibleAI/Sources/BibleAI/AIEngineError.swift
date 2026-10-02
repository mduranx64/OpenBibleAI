//
//  AIEngineError.swift
//  BibleAI
//

import Foundation

/// Engine-independent failures, with messages suitable for the study panel.
public enum AIEngineError: LocalizedError, Equatable, Sendable {
    case contextTooLong
    case refused
    case unsupportedLanguage
    case modelUnavailable
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .contextTooLong:
            "The verse and chapter context are too long for the on-device model. Try a shorter question."
        case .refused:
            "The on-device model declined to answer this question."
        case .unsupportedLanguage:
            "The on-device model doesn’t support this language."
        case .modelUnavailable:
            "The on-device model isn’t available right now."
        case .timedOut:
            "The on-device model took too long to respond. Please try again."
        }
    }
}
