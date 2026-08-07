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
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let combined = try Data(contentsOf: url)
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode([SharedPassPasskeyItem].self, from: decrypted)
        } catch {
            Log.autofill.error("Pending passkey queue exists but is unreadable: \(String(describing: error), privacy: .public)")
            throw SharedPendingItemsStoreError.unreadable(error)
        }
    }

    /// Append a passkey to the pending queue
    static func append(
        _ item: SharedPassPasskeyItem,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }

        var items: [SharedPassPasskeyItem]
        do {
            items = try load(key: key, fileURL: url)
        } catch SharedPendingItemsStoreError.unreadable {
            // Never overwrite an unreadable queue — it may hold unsynced passkey
            // private keys. Move it aside so it stays recoverable on disk.
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: url, to: backup)
            Log.autofill.fault("Moved unreadable pending passkey queue aside to \(backup.lastPathComponent, privacy: .public)")
            items = []
        }
        items.append(item)

        let data = try JSONEncoder().encode(items)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw SharedCryptoError.decryptionFailed
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try combined.write(to: url, options: .atomic)
    }

    /// Remove one passkey from the queue by credential id.
    ///
    /// Needed because a push succeeds for one item at a time: `clear()` would
    /// discard any other passkey queued alongside it, and those hold private
    /// keys that exist nowhere else yet.
    static func remove(
        credentialId: String,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }

        let items = try load(key: key, fileURL: url)
        let remaining = items.filter { $0.credentialId != credentialId }
        guard remaining.count != items.count else { return }

        if remaining.isEmpty {
            clear(fileURL: url)
            return
        }

        let data = try JSONEncoder().encode(remaining)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw SharedCryptoError.decryptionFailed
        }
        try combined.write(to: url, options: .atomic)
    }

    /// Remove the pending queue (after the main app has merged it)
    static func clear(fileURL: URL? = SharedPendingItemsStore.defaultFileURL) {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.autofill.error("Failed to clear pending passkey queue: \(String(describing: error), privacy: .public)")
        }
    }
}
