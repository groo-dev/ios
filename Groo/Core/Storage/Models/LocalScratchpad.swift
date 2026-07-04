//
//  LocalScratchpad.swift
//  Groo
//
//  SwiftData model for locally cached scratchpads.
//  Stores encrypted data (same format as server) for security.
//  Decryption happens on-demand in memory.
//

import Foundation
import SwiftData
import os

@Model
final class LocalScratchpad {
    @Attribute(.unique) var id: String

    /// Encrypted content payload as JSON string (contains ciphertext, iv, version)
    var encryptedContentJSON: String

    /// File attachments with encrypted metadata as JSON
    var filesJSON: Data?

    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date

    init(
        id: String,
        encryptedContentJSON: String,
        createdAt: Date,
        updatedAt: Date,
        syncedAt: Date = Date(),
        filesJSON: Data? = nil
    ) {
        self.id = id
        self.encryptedContentJSON = encryptedContentJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.filesJSON = filesJSON
    }

    /// Get encrypted content payload
    var encryptedContent: PadEncryptedPayload? {
        guard let data = encryptedContentJSON.data(using: .utf8) else {
            Log.scratchpad.error("Scratchpad \(self.id, privacy: .public): encryptedContentJSON is not valid UTF-8")
            return nil
        }
        do {
            return try JSONDecoder().decode(PadEncryptedPayload.self, from: data)
        } catch {
            Log.scratchpad.error("Scratchpad \(self.id, privacy: .public): failed to decode encrypted content payload: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Get encrypted file attachments
    var files: [PadFileAttachment] {
        get {
            guard let data = filesJSON else { return [] }
            do {
                return try JSONDecoder().decode([PadFileAttachment].self, from: data)
            } catch {
                Log.scratchpad.error("Scratchpad \(self.id, privacy: .public): failed to decode file attachments: \(String(describing: error), privacy: .public)")
                return []
            }
        }
        set {
            do {
                filesJSON = try JSONEncoder().encode(newValue)
            } catch {
                // Keep the previous value rather than silently dropping attachments
                Log.scratchpad.error("Scratchpad \(self.id, privacy: .public): failed to encode file attachments: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

// MARK: - Conversion from API Model

extension LocalScratchpad {
    /// Create from API model (PadScratchpad) - stores encrypted data directly.
    /// Fails (returns nil) if the payload can't be encoded, so callers skip
    /// caching instead of storing a "{}" placeholder ciphertext.
    convenience init?(from apiScratchpad: PadScratchpad) {
        let encryptedJSON: String
        do {
            let data = try JSONEncoder().encode(apiScratchpad.encryptedContent)
            guard let json = String(data: data, encoding: .utf8) else {
                Log.scratchpad.error("Scratchpad \(apiScratchpad.id, privacy: .public): encoded payload is not valid UTF-8; skipping local cache")
                return nil
            }
            encryptedJSON = json
        } catch {
            Log.scratchpad.error("Scratchpad \(apiScratchpad.id, privacy: .public): failed to encode payload: \(String(describing: error), privacy: .public); skipping local cache")
            return nil
        }

        let filesJSON: Data?
        do {
            filesJSON = try JSONEncoder().encode(apiScratchpad.files)
        } catch {
            Log.scratchpad.error("Scratchpad \(apiScratchpad.id, privacy: .public): failed to encode file attachments: \(String(describing: error), privacy: .public)")
            filesJSON = nil
        }

        self.init(
            id: apiScratchpad.id,
            encryptedContentJSON: encryptedJSON,
            createdAt: Date(timeIntervalSince1970: Double(apiScratchpad.createdAt) / 1000),
            updatedAt: Date(timeIntervalSince1970: Double(apiScratchpad.updatedAt) / 1000),
            filesJSON: filesJSON
        )
    }

    /// Convert back to API model for pending operations
    func toPadScratchpad() -> PadScratchpad? {
        guard let encryptedContent = encryptedContent else { return nil }
        return PadScratchpad(
            id: id,
            encryptedContent: encryptedContent,
            files: files,
            createdAt: Int(createdAt.timeIntervalSince1970 * 1000),
            updatedAt: Int(updatedAt.timeIntervalSince1970 * 1000)
        )
    }
}
