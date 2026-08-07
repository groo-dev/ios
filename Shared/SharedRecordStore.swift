//
//  SharedRecordStore.swift
//  Groo
//
//  App Group cache of per-item vault records, so the AutoFill extension can
//  refresh from the server itself instead of showing whatever the main app last
//  wrote.
//
//  Records are stored in the server's own shape. Their payloads are already
//  encrypted under per-record keys, but the file is sealed again with the vault
//  key so ids and seqs are not left in the clear — matching how the pending
//  passkey queue is stored.
//
//  This deliberately does NOT reuse the blob cache: refreshing that would mean
//  decoding through `SharedPassVault`, whose `case other` collapses notes,
//  cards, bank accounts, files and wallets into nothing, and re-encoding it
//  would destroy them.
//

import CryptoKit
import Foundation
import os

enum SharedRecordStoreError: Error {
    case containerNotAvailable
    case unreadable(any Error)
}

enum SharedRecordStore {
    /// Records plus the cursor they were synced to.
    struct Cached: Codable, Equatable {
        var records: [SharedServerRecord]
        var cursor: Int

        static let empty = Cached(records: [], cursor: 0)
    }

    private static let fileManager = FileManager.default

    /// Test seam, mirroring `SharedVaultStore`. Production never sets this.
    nonisolated(unsafe) static var overrideDirectoryURL: URL?

    static var defaultFileURL: URL? {
        let base: URL? =
            overrideDirectoryURL
            ?? fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier
            )
        return base?
            .appendingPathComponent("pass", isDirectory: true)
            .appendingPathComponent("records.enc")
    }

    /// Returns nil when nothing has been cached yet. Throws `.unreadable` when a
    /// file exists but cannot be opened — callers must not treat that as "empty",
    /// or a transient fault would silently wipe the cursor and force a full
    /// resync of every record.
    static func load(
        key: SymmetricKey,
        fileURL: URL? = SharedRecordStore.defaultFileURL
    ) throws -> Cached? {
        guard let url = fileURL else { throw SharedRecordStoreError.containerNotAvailable }
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let sealed = try AES.GCM.SealedBox(combined: try Data(contentsOf: url))
            let plaintext = try AES.GCM.open(sealed, using: key)
            return try JSONDecoder().decode(Cached.self, from: plaintext)
        } catch {
            Log.autofill.error(
                "Record cache exists but is unreadable: \(String(describing: error), privacy: .public)"
            )
            throw SharedRecordStoreError.unreadable(error)
        }
    }

    static func save(
        _ cached: Cached,
        key: SymmetricKey,
        fileURL: URL? = SharedRecordStore.defaultFileURL
    ) throws {
        guard let url = fileURL else { throw SharedRecordStoreError.containerNotAvailable }

        let data = try JSONEncoder().encode(cached)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw SharedCryptoError.decryptionFailed
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try combined.write(to: url, options: .atomic)
    }

    static func clear(fileURL: URL? = SharedRecordStore.defaultFileURL) {
        guard let url = fileURL, fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Log.autofill.error(
                "Failed to clear record cache: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Apply a delta page, returning the merged cache.
    ///
    /// Tombstones remove; the cursor never moves backwards, so a stale response
    /// cannot rewind past records already applied.
    static func apply(
        _ cached: Cached,
        page: SharedRecordsResponse
    ) -> Cached {
        var byId = Dictionary(uniqueKeysWithValues: cached.records.map { ($0.id, $0) })
        for record in page.records {
            if record.isDeleted {
                byId.removeValue(forKey: record.id)
            } else {
                byId[record.id] = record
            }
        }
        return Cached(
            records: byId.values.sorted { $0.seq < $1.seq },
            cursor: max(cached.cursor, page.nextSeq)
        )
    }
}
