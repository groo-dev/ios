//
//  SharedPendingPasswordsStore.swift
//  Groo
//
//  Queue for logins created in the AutoFill extension, encrypted with the
//  vault key until the main app merges them into the vault and syncs.
//
//  A separate file from `pending_passkeys.enc` on purpose: that file holds
//  unsynced passkey private keys, and no format change to it is worth the risk
//  of losing them.
//

import CryptoKit
import Foundation

enum SharedPendingPasswordsStore {
    /// Production queue location inside the App Group container. Tests pass an
    /// explicit temp-directory URL instead of touching this file.
    static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)?
            .appendingPathComponent("pass", isDirectory: true)
            .appendingPathComponent("pending_passwords.enc")
    }

    static func load(
        key: SymmetricKey,
        fileURL: URL? = SharedPendingPasswordsStore.defaultFileURL
    ) throws -> [SharedPendingPasswordItem] {
        try SharedPendingQueue.load(SharedPendingPasswordItem.self, key: key, fileURL: fileURL)
    }

    static func append(
        _ item: SharedPendingPasswordItem,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingPasswordsStore.defaultFileURL
    ) throws {
        try SharedPendingQueue.append(item, key: key, fileURL: fileURL)
    }

    static func clear(fileURL: URL? = SharedPendingPasswordsStore.defaultFileURL) {
        SharedPendingQueue.clear(fileURL: fileURL)
    }
}
