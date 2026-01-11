//
//  PadService.swift
//  Groo
//
//  Pad feature service - handles encryption/decryption and local state.
//  Decrypts items on-demand from encrypted local storage.
//

import UIKit
import CryptoKit
import Foundation

// MARK: - Errors

enum PadError: Error {
    case notAuthenticated
    case noEncryptionKey
    case encryptionNotSetup
    case decryptionFailed
    case apiError(Error)
}

// MARK: - PadService

@MainActor
@Observable
class PadService {
    // Dependencies
    private let api: APIClient
    private let crypto: CryptoService
    private let keychain: KeychainService
    private let store: LocalStore

    // Encryption key (derived from password, in-memory only)
    private var encryptionKey: SymmetricKey?
    private(set) var hasEncryptionSetup = false

    init(
        api: APIClient,
        crypto: CryptoService = CryptoService(),
        keychain: KeychainService = KeychainService(),
        store: LocalStore = .shared
    ) {
        self.api = api
        self.crypto = crypto
        self.keychain = keychain
        self.store = store
    }

    // MARK: - Encryption Setup

    /// Check if encryption is already set up for this user
    func checkEncryptionSetup() async throws -> Bool {
        let state: PadUserState = try await api.get(APIClient.Endpoint.state)
        hasEncryptionSetup = state.encryptionSalt != nil && state.encryptionTest != nil
        return hasEncryptionSetup
    }

    /// Unlock with existing password - derives encryption key and stores in Keychain
    func unlock(password: String) async throws -> Bool {
        let state: PadUserState = try await api.get(APIClient.Endpoint.state)

        guard let saltBase64 = state.encryptionSalt,
              let salt = Data(base64Encoded: saltBase64),
              let testPayload = state.encryptionTest else {
            throw PadError.encryptionNotSetup
        }

        let key = try crypto.deriveKey(password: password, salt: salt)

        // Verify the key by decrypting the test payload
        let encPayload = testPayload.toEncryptedPayload()

        if crypto.verifyKey(key, with: encPayload) {
            encryptionKey = key
            // Store key in Keychain with biometric protection for extensions
            storeKeyInKeychain(key)
            return true
        }

        return false
    }

    /// Try to unlock using biometric authentication (retrieve key from Keychain)
    func unlockWithBiometric() throws -> Bool {
        let keyData = try keychain.loadBiometricProtected(for: KeychainService.Key.padEncryptionKey)
        encryptionKey = SymmetricKey(data: keyData)
        return true
    }

    /// Check if biometric unlock is available
    var canUnlockWithBiometric: Bool {
        keychain.biometricProtectedKeyExists(for: KeychainService.Key.padEncryptionKey)
    }

    /// Lock the service (clear encryption key from memory)
    func lock() {
        encryptionKey = nil
        // Note: We keep the key in Keychain for biometric unlock later
    }

    /// Lock and clear stored key (full sign out)
    func lockAndClearKey() {
        encryptionKey = nil
        try? keychain.deleteBiometricProtected(for: KeychainService.Key.padEncryptionKey)
    }

    /// Store encryption key in Keychain with biometric protection
    private func storeKeyInKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        try? keychain.saveBiometricProtected(keyData, for: KeychainService.Key.padEncryptionKey)
    }

    var isUnlocked: Bool {
        encryptionKey != nil
    }

    // MARK: - Get Decrypted Items (from local encrypted storage)

    /// Get all items from local storage, decrypted in memory
    func getDecryptedItems() throws -> [DecryptedListItem] {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedItems = store.getAllPadItems()
        var decrypted: [DecryptedListItem] = []

        for item in encryptedItems {
            if let decryptedItem = try? decryptItem(item, using: key) {
                decrypted.append(decryptedItem)
            }
        }

        return decrypted
    }

    private func decryptItem(_ item: LocalPadItem, using key: SymmetricKey) throws -> DecryptedListItem {
        guard let encryptedPayload = item.encryptedText else {
            throw PadError.decryptionFailed
        }

        let text = try crypto.decrypt(encryptedPayload.toEncryptedPayload(), using: key)
        let files = try decryptFileAttachments(item.files, using: key)

        return DecryptedListItem(
            id: item.id,
            text: text,
            files: files,
            createdAt: Int(item.createdAt.timeIntervalSince1970 * 1000)
        )
    }

    private func decryptFileAttachments(_ files: [PadFileAttachment], using key: SymmetricKey) throws -> [DecryptedFileAttachment] {
        var decrypted: [DecryptedFileAttachment] = []

        for file in files {
            let name = try crypto.decrypt(file.encryptedName.toEncryptedPayload(), using: key)
            let type = try crypto.decrypt(file.encryptedType.toEncryptedPayload(), using: key)
            decrypted.append(DecryptedFileAttachment(
                id: file.id,
                name: name,
                type: type,
                size: file.size,
                r2Key: file.r2Key
            ))
        }

        return decrypted
    }

    // MARK: - Create Encrypted Item

    /// Create an encrypted item for storing locally and syncing
    func createEncryptedItem(text: String) throws -> PadListItem {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedText = try crypto.encrypt(text, using: key)

        return PadListItem(
            id: String(UUID().uuidString.prefix(8).lowercased()),
            encryptedText: encryptedText.toPadEncryptedPayload(),
            files: [],
            createdAt: Int(Date().timeIntervalSince1970 * 1000)
        )
    }

    // MARK: - File Operations

    /// Download and decrypt a file
    func downloadFile(_ file: DecryptedFileAttachment) async throws -> Data {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedData = try await api.downloadFile(from: APIClient.Endpoint.file(file.r2Key))
        return try crypto.decryptData(encryptedData, using: key)
    }

    /// Encrypt and upload a file
    func uploadFile(name: String, type: String, data: Data) async throws -> PadFileAttachment {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        // Encrypt the file data
        let encryptedData = try crypto.encryptData(data, using: key)

        // Encrypt the metadata
        let encryptedName = try crypto.encrypt(name, using: key)
        let encryptedType = try crypto.encrypt(type, using: key)

        // Upload
        let response = try await api.uploadFile(encryptedData, to: APIClient.Endpoint.files)

        return PadFileAttachment(
            id: response.id,
            encryptedName: encryptedName.toPadEncryptedPayload(),
            size: response.size,
            encryptedType: encryptedType.toPadEncryptedPayload(),
            r2Key: response.r2Key
        )
    }

    // MARK: - Copy to Clipboard

    /// Copy text to system clipboard
    func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}
