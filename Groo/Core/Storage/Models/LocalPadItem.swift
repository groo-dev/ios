//
//  LocalPadItem.swift
//  Groo
//
//  SwiftData model for locally cached Pad items.
//  Stores encrypted data (same format as server) for security.
//  Decryption happens on-demand in memory.
//

import Foundation
import SwiftData
import os

@Model
final class LocalPadItem {
    @Attribute(.unique) var id: String

    /// Encrypted text payload as JSON string (contains ciphertext, iv, version)
    var encryptedTextJSON: String

    /// File attachments with encrypted metadata as JSON
    var filesJSON: Data?

    var createdAt: Date
    var syncedAt: Date

    init(id: String, encryptedTextJSON: String, createdAt: Date, syncedAt: Date = Date(), filesJSON: Data? = nil) {
        self.id = id
        self.encryptedTextJSON = encryptedTextJSON
        self.createdAt = createdAt
        self.syncedAt = syncedAt
        self.filesJSON = filesJSON
    }

    /// Get encrypted text payload
    var encryptedText: PadEncryptedPayload? {
        guard let data = encryptedTextJSON.data(using: .utf8) else {
            Log.pad.error("Item \(self.id, privacy: .public): encryptedTextJSON is not valid UTF-8")
            return nil
        }
        do {
            return try JSONDecoder().decode(PadEncryptedPayload.self, from: data)
        } catch {
            Log.pad.error("Item \(self.id, privacy: .public): failed to decode encrypted text payload: \(String(describing: error), privacy: .public)")
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
                Log.pad.error("Item \(self.id, privacy: .public): failed to decode file attachments: \(String(describing: error), privacy: .public)")
                return []
            }
        }
        set {
            do {
                filesJSON = try JSONEncoder().encode(newValue)
            } catch {
                // Keep the previous value rather than silently dropping attachments
                Log.pad.error("Item \(self.id, privacy: .public): failed to encode file attachments: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

// MARK: - Conversion from API Model

extension LocalPadItem {
    /// Create from API model (PadListItem) - stores encrypted data directly.
    /// Fails (returns nil) if the payload can't be encoded, so callers skip
    /// caching instead of storing a "{}" placeholder ciphertext.
    convenience init?(from apiItem: PadListItem) {
        let encryptedJSON: String
        do {
            let data = try JSONEncoder().encode(apiItem.encryptedText)
            guard let json = String(data: data, encoding: .utf8) else {
                Log.pad.error("Item \(apiItem.id, privacy: .public): encoded payload is not valid UTF-8; skipping local cache")
                return nil
            }
            encryptedJSON = json
        } catch {
            Log.pad.error("Item \(apiItem.id, privacy: .public): failed to encode payload: \(String(describing: error), privacy: .public); skipping local cache")
            return nil
        }

        let filesJSON: Data?
        do {
            filesJSON = try JSONEncoder().encode(apiItem.files)
        } catch {
            Log.pad.error("Item \(apiItem.id, privacy: .public): failed to encode file attachments: \(String(describing: error), privacy: .public)")
            filesJSON = nil
        }

        self.init(
            id: apiItem.id,
            encryptedTextJSON: encryptedJSON,
            createdAt: Date(timeIntervalSince1970: Double(apiItem.createdAt) / 1000),
            filesJSON: filesJSON
        )
    }

    /// Convert back to API model for pending operations
    func toPadListItem() -> PadListItem? {
        guard let encryptedText = encryptedText else { return nil }
        return PadListItem(
            id: id,
            encryptedText: encryptedText,
            files: files,
            createdAt: Int(createdAt.timeIntervalSince1970 * 1000)
        )
    }
}
