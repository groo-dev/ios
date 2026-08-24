//
//  SharedPendingItemsStore.swift
//  Groo
//
//  Queue for passkeys created by the AutoFill extension.
//  The extension can't push to the Pass server, so new passkeys are stored
//  here (encrypted with the vault key) until the main app merges them into
//  the vault and syncs.
//

import CryptoKit
import Foundation
import os

enum SharedPendingItemsStoreError: Error {
    case containerNotAvailable
    case unreadable(Error)
}

enum SharedPendingItemsStore {
    /// Production queue location inside the App Group container. Tests pass
    /// an explicit temp-directory URL instead of touching this file.
    static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)?
            .appendingPathComponent("pass", isDirectory: true)
            .appendingPathComponent("pending_passkeys.enc")
    }

    /// Load pending passkeys. Returns [] only when no queue file exists.
    /// Throws `.unreadable` when the file exists but can't be decrypted/decoded —
    /// callers must NOT treat that as an empty queue.
    static func load(
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws -> [SharedPassPasskeyItem] {
        try SharedPendingQueue.load(SharedPassPasskeyItem.self, key: key, fileURL: fileURL)
    }

    /// Append a passkey to the pending queue
    static func append(
        _ item: SharedPassPasskeyItem,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws {
        try SharedPendingQueue.append(item, key: key, fileURL: fileURL)
    }

    /// Remove the pending queue (after the main app has merged it)
    static func clear(fileURL: URL? = SharedPendingItemsStore.defaultFileURL) {
        SharedPendingQueue.clear(fileURL: fileURL)
    }
}
