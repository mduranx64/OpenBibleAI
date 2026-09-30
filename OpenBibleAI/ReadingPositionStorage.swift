//
//  ReadingPositionStorage.swift
//  OpenBibleAI
//
//  Created by Miguel Duran on 30-09-26.
//

import Foundation

/// The subset of `UserDefaults` that `ReadingPositionStore` relies on.
/// Abstracting it lets tests use an in-memory fake instead of the real
/// `UserDefaults`, avoiding shared state and leftover suite files on disk.
protocol ReadingPositionStorage {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: ReadingPositionStorage {}
