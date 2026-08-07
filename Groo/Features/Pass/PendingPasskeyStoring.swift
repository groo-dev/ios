//
//  PendingPasskeyStoring.swift
//  Groo
//
//  Seam over SharedPendingItemsStore so tests can drive the queue the AutoFill
//  extension writes to without touching the real App Group container.
//

import CryptoKit

protocol PendingPasskeyStoring {
    func load(key: SymmetricKey) throws -> [SharedPassPasskeyItem]
    func clear()
}

/// Production implementation, backed by the App Group queue file.
struct SharedPendingPasskeyStore: PendingPasskeyStoring {
    func load(key: SymmetricKey) throws -> [SharedPassPasskeyItem] {
        try SharedPendingItemsStore.load(key: key)
    }

    func clear() {
        SharedPendingItemsStore.clear()
    }
}
