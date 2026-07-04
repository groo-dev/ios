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

enum SharedPendingItemsStore {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)?
            .appendingPathComponent("pass", isDirectory: true)
            .appendingPathComponent("pending_passkeys.enc")
    }

    /// Load pending passkeys. Returns [] if none or on decryption failure.
    static func load(key: SymmetricKey) -> [SharedPassPasskeyItem] {
        guard let url = fileURL,
              let combined = try? Data(contentsOf: url),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let decrypted = try? AES.GCM.open(sealedBox, using: key),
              let items = try? JSONDecoder().decode([SharedPassPasskeyItem].self, from: decrypted) else {
            return []
        }
        return items
    }

    /// Append a passkey to the pending queue
    static func append(_ item: SharedPassPasskeyItem, key: SymmetricKey) throws {
        guard let url = fileURL else {
            throw SharedVaultStoreError.containerNotAvailable
        }

        var items = load(key: key)
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

    /// Remove the pending queue (after the main app has merged it)
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
