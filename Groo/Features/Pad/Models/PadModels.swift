//
//  PadModels.swift
//  Groo
//
//  Data models for Pad feature - matches API types exactly.
//

import Foundation

// MARK: - Encrypted Payload

/// Encrypted data with IV and version info
struct PadEncryptedPayload: Codable, Equatable {
    let ciphertext: String  // base64 encoded
    let iv: String          // base64 encoded, 12 bytes
    let version: Int        // encryption version for future migrations
}

// MARK: - File Attachment

/// File attachment with encrypted metadata
struct PadFileAttachment: Codable, Identifiable, Equatable {
    let id: String
    let encryptedName: PadEncryptedPayload
    let size: Int           // encrypted size
    let encryptedType: PadEncryptedPayload
    let r2Key: String
}

// MARK: - List Item

/// List item with encrypted text and optional files
struct PadListItem: Codable, Identifiable, Equatable {
    let id: String
    let encryptedText: PadEncryptedPayload
    let files: [PadFileAttachment]
    let createdAt: Int      // Unix timestamp in milliseconds
}

// MARK: - Scratchpad

/// Scratchpad with encrypted content
struct PadScratchpad: Codable, Identifiable, Equatable {
    let id: String
    let encryptedContent: PadEncryptedPayload
    let files: [PadFileAttachment]
    let createdAt: Int
    let updatedAt: Int
}

// MARK: - User State

/// Complete user state from the API
struct PadUserState: Codable, Equatable {
    let activeId: String
    let scratchpads: [String: PadScratchpad]
    let list: [PadListItem]
    let encryptionSalt: String?         // base64 encoded salt for key derivation
    let encryptionTest: PadEncryptedPayload?  // encrypted "test" string to verify password
    let deviceTokens: [PadDeviceToken]?
}

// MARK: - Device Token

/// APNs device token for push notifications
struct PadDeviceToken: Codable, Equatable {
    let token: String
    let platform: String    // "macos" or "ios"
    let environment: String // "production" or "development"
    let registeredAt: Int
    let lastUsedAt: Int
}

// MARK: - Decrypted Models (for display)

/// Decrypted list item for UI display
struct DecryptedListItem: Identifiable, Equatable {
    let id: String
    let text: String
    let files: [DecryptedFileAttachment]
    let createdAt: Date

    init(id: String, text: String, files: [DecryptedFileAttachment], createdAt: Int) {
        self.id = id
        self.text = text
        self.files = files
        self.createdAt = Date(timeIntervalSince1970: Double(createdAt) / 1000)
    }
}

/// Decrypted file attachment for UI display
struct DecryptedFileAttachment: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let size: Int
    let r2Key: String
}

// MARK: - Conversion Helpers

extension PadEncryptedPayload {
    /// Convert to CryptoService's EncryptedPayload
    func toEncryptedPayload() -> EncryptedPayload {
        EncryptedPayload(ciphertext: ciphertext, iv: iv, version: version)
    }
}

extension EncryptedPayload {
    /// Convert to PadEncryptedPayload for API
    func toPadEncryptedPayload() -> PadEncryptedPayload {
        PadEncryptedPayload(ciphertext: ciphertext, iv: iv, version: version)
    }
}
