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
        guard let data = encryptedContentJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PadEncryptedPayload.self, from: data)
    }

    /// Get encrypted file attachments
    var files: [PadFileAttachment] {
        get {
            guard let data = filesJSON else { return [] }
            return (try? JSONDecoder().decode([PadFileAttachment].self, from: data)) ?? []
        }
        set {
            filesJSON = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Conversion from API Model

extension LocalScratchpad {
    /// Create from API model (PadScratchpad) - stores encrypted data directly
    convenience init(from apiScratchpad: PadScratchpad) {
        let encryptedJSON = (try? JSONEncoder().encode(apiScratchpad.encryptedContent))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        self.init(
            id: apiScratchpad.id,
            encryptedContentJSON: encryptedJSON,
            createdAt: Date(timeIntervalSince1970: Double(apiScratchpad.createdAt) / 1000),
            updatedAt: Date(timeIntervalSince1970: Double(apiScratchpad.updatedAt) / 1000),
            filesJSON: try? JSONEncoder().encode(apiScratchpad.files)
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
