//
//  SharedPendingQueue.swift
//  Groo
//
//  Encrypted append-only queue in the App Group container, shared by the
//  pending-passkey and pending-password stores.
//
//  Extracted rather than copied so the "never overwrite an unreadable queue"
//  rule has exactly one implementation. That rule protects material — passkey
//  private keys, and now passwords — that exists nowhere else until the main
//  app drains it.
//

import CryptoKit
import Foundation
import os

enum SharedPendingQueue {
    /// Load the queue. Returns [] only when no file exists.
    /// Throws `.unreadable` when the file exists but cannot be decrypted or
    /// decoded — callers must NOT treat that as an empty queue.
    static func load<T: Decodable>(
        _ type: T.Type,
        key: SymmetricKey,
        fileURL: URL?
    ) throws -> [T] {
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
            return try JSONDecoder().decode([T].self, from: decrypted)
        } catch {
            Log.autofill.error(
                "Pending queue \(url.lastPathComponent, privacy: .public) exists but is unreadable: \(String(describing: error), privacy: .public)"
            )
            throw SharedPendingItemsStoreError.unreadable(error)
        }
    }

    static func append<T: Codable>(
        _ item: T,
        key: SymmetricKey,
        fileURL: URL?
    ) throws {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }

        var items: [T]
        do {
            items = try load(T.self, key: key, fileURL: url)
        } catch SharedPendingItemsStoreError.unreadable {
            // Never overwrite an unreadable queue — it may hold the only copy
            // of a credential. Move it aside so it stays recoverable on disk.
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: url, to: backup)
            Log.autofill.fault(
                "Moved unreadable pending queue aside to \(backup.lastPathComponent, privacy: .public)"
            )
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

    static func clear(fileURL: URL?) {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.autofill.error(
                "Failed to clear pending queue \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
