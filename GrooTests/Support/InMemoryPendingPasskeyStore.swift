//
//  InMemoryPendingPasskeyStore.swift
//  GrooTests
//
//  PendingPasskeyStoring fake standing in for the App Group queue the AutoFill
//  extension writes to.
//

import CryptoKit
import Foundation
@testable import Groo

final class InMemoryPendingPasskeyStore: PendingPasskeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [SharedPassPasskeyItem] = []
    private var _clearCount = 0

    /// Set to make `load` throw, standing in for an unreadable queue file.
    var loadError: Error?

    var items: [SharedPassPasskeyItem] {
        get { lock.withLock { _items } }
        set { lock.withLock { _items = newValue } }
    }

    /// How many times the queue was cleared — a merge that fails must not clear.
    var clearCount: Int { lock.withLock { _clearCount } }

    func load(key: SymmetricKey) throws -> [SharedPassPasskeyItem] {
        if let loadError { throw loadError }
        return items
    }

    func clear() {
        lock.withLock {
            _clearCount += 1
            _items = []
        }
    }
}
