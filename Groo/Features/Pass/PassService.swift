//
//  PassService.swift
//  Groo
//
//  Pass feature service - handles vault encryption/decryption and sync.
//  Vault is decrypted in-memory only, stored encrypted locally and on server.
//

import UIKit
import CryptoKit
import Foundation
import LocalAuthentication
import os

// MARK: - Errors

enum PassError: Error, LocalizedError {
    case notAuthenticated
    case noEncryptionKey
    case vaultNotSetup
    case decryptionFailed
    case vaultVersionConflict(serverVersion: Int, localVersion: Int)
    case apiError(Error)
    case invalidVaultData

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .noEncryptionKey:
            return "Vault is locked"
        case .vaultNotSetup:
            return "Vault not set up"
        case .decryptionFailed:
            return "Failed to decrypt vault"
        case .vaultVersionConflict(let server, let local):
            return "Version conflict: server=\(server), local=\(local)"
        case .apiError(let error):
            return "API error: \(error.localizedDescription)"
        case .invalidVaultData:
            return "Invalid vault data"
        }
    }
}

// MARK: - PassService

@MainActor
@Observable
class PassService {
    // Dependencies
    private let api: PassAPIClient
    private let crypto: CryptoService
    private let keychain: any KeychainServicing
    private let vaultStore: PassVaultStore
    private let credentialService: CredentialIdentityService

    // Encryption state
    private var encryptionKey: SymmetricKey?
    private var keySalt: Data?
    private var kdfIterations: UInt32 = 600_000

    // Cached decrypted vault (in-memory only)
    private var vault: PassVault?
    private var serverVersion: Int = 0

    // State
    private(set) var hasVaultSetup = false
    private(set) var isLoading = false
    private(set) var lastError: String?

    init(
        api: PassAPIClient? = nil,
        crypto: CryptoService = CryptoService(),
        keychain: any KeychainServicing = KeychainService(),
        vaultStore: PassVaultStore = PassVaultStore(),
        credentialService: CredentialIdentityService = CredentialIdentityService(),
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized }
    ) {
        self.api = api ?? PassAPIClient(tokenProvider: tokenProvider, forceRefresh: forceRefresh)
        self.crypto = crypto
        self.keychain = keychain
        self.vaultStore = vaultStore
        self.credentialService = credentialService
    }

    // MARK: - State Properties

    var isUnlocked: Bool {
        encryptionKey != nil && vault != nil
    }

    var canUnlockWithBiometric: Bool {
        keychain.biometricProtectedKeyExists(for: KeychainService.Key.passEncryptionKey)
    }

    // MARK: - Vault Setup Check

    /// Check if vault is set up on server
    func checkVaultSetup() async {
        do {
            let keyInfo: PassKeyInfo = try await api.get(PassAPIClient.Endpoint.keyInfo)
            hasVaultSetup = true
            kdfIterations = UInt32(keyInfo.kdfIterations)
            if let salt = Data(base64Encoded: keyInfo.keySalt) {
                keySalt = salt
            }
        } catch APIError.httpError(let statusCode, _) where statusCode == 404 {
            // 404 means no vault setup yet
            hasVaultSetup = false
        } catch {
            // Offline or server error — not proof the vault doesn't exist
            Log.pass.error("checkVaultSetup failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Unlock Flow

    /// Unlock vault with master password
    func unlock(password: String) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        // Get key info from server
        let keyInfo: PassKeyInfo = try await api.get(PassAPIClient.Endpoint.keyInfo)
        guard let salt = Data(base64Encoded: keyInfo.keySalt) else {
            throw PassError.vaultNotSetup
        }

        keySalt = salt
        kdfIterations = UInt32(keyInfo.kdfIterations)

        // Derive encryption key using server-provided iterations
        let key = try crypto.deriveKey(password: password, salt: salt, iterations: kdfIterations)

        // Fetch and decrypt vault to verify password
        let vaultResponse: PassVaultResponse = try await api.get(PassAPIClient.Endpoint.vault)

        guard let encryptedData = Data(base64Encoded: vaultResponse.encryptedData),
              let iv = Data(base64Encoded: vaultResponse.iv) else {
            throw PassError.invalidVaultData
        }

        // Decrypt vault
        let decryptedData = try decryptVaultData(encryptedData, iv: iv, using: key)

        // Decryption succeeded, so a decode failure is a schema bug — not a wrong password
        let decryptedVault: PassVault
        do {
            decryptedVault = try JSONDecoder().decode(PassVault.self, from: decryptedData)
        } catch {
            Log.pass.error("Vault JSON decode failed after password unlock: \(String(describing: error), privacy: .public)")
            throw PassError.invalidVaultData
        }

        // Success - store key and vault
        encryptionKey = key
        vault = decryptedVault
        serverVersion = vaultResponse.version
        hasVaultSetup = true

        // Store key in Keychain with biometric protection
        storeKeyInKeychain(key)

        // Store salt for biometric unlock
        do {
            try keychain.save(salt, for: KeychainService.Key.passSalt)
        } catch {
            // Biometric unlock will throw vaultNotSetup later without this salt
            Log.pass.error("Failed to store pass salt: \(String(describing: error), privacy: .public)")
        }

        // Save encrypted vault locally
        let metadata = PassVaultMetadata(
            version: vaultResponse.version,
            iv: vaultResponse.iv,
            updatedAt: vaultResponse.updatedAt,
            lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        await saveVaultCache(encryptedData: encryptedData, metadata: metadata)

        // Register AutoFill QuickType suggestions
        await credentialService.updateCredentialIdentities(from: decryptedVault.items)

        // Pick up passkeys created by the AutoFill extension
        await mergePendingPasskeys()

        return true
    }

    /// Write the encrypted vault into the App Group cache the AutoFill extension
    /// reads. A silent failure here means AutoFill serves stale credentials.
    private func saveVaultCache(encryptedData: Data, metadata: PassVaultMetadata) async {
        do {
            try await vaultStore.saveVault(encryptedData: encryptedData, metadata: metadata)
        } catch {
            Log.pass.error("Failed to write vault cache for AutoFill: \(String(describing: error), privacy: .public)")
        }
    }

    /// Unlock using biometric authentication
    /// - Parameter context: Optional shared LAContext for reusing authentication within a session
    func unlockWithBiometric(context: LAContext? = nil) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        // Load key from Keychain (triggers Face ID/Touch ID)
        let keyData = try keychain.loadBiometricProtected(
            for: KeychainService.Key.passEncryptionKey,
            prompt: "Authenticate to unlock Pass",
            context: context
        )
        let key = SymmetricKey(data: keyData)

        // Load salt
        let salt: Data
        do {
            salt = try keychain.load(for: KeychainService.Key.passSalt)
        } catch KeychainError.itemNotFound {
            throw PassError.vaultNotSetup
        } catch {
            // A keychain fault is not "never set up" — keep the real cause
            Log.pass.error("Failed to load pass salt: \(String(describing: error), privacy: .public)")
            throw error
        }
        keySalt = salt

        // Try to load from local cache first
        if let cached = try? await vaultStore.loadVault() {
            do {
                let decryptedData = try decryptVaultData(
                    cached.data,
                    iv: Data(base64Encoded: cached.metadata.iv) ?? Data(),
                    using: key
                )

                // Decode inside the do block so a corrupt cache is also cleared
                let decryptedVault = try JSONDecoder().decode(PassVault.self, from: decryptedData)

                encryptionKey = key
                vault = decryptedVault
                serverVersion = cached.metadata.version
                hasVaultSetup = true

                // Register AutoFill QuickType suggestions even if background sync fails
                await credentialService.updateCredentialIdentities(from: decryptedVault.items)

                // Sync in background, then pick up passkeys created by the AutoFill extension
                Task {
                    do {
                        try await sync()
                    } catch {
                        Log.pass.error("Background sync after unlock failed: \(String(describing: error), privacy: .public)")
                    }
                    await mergePendingPasskeys()
                }

                return true
            } catch {
                // Local cache unusable - clear it and fall through to server
                Log.pass.error("Vault cache unusable, refetching from server: \(String(describing: error), privacy: .public)")
                try? await vaultStore.clear()
            }
        }

        // Fallback to server fetch
        let vaultResponse: PassVaultResponse = try await api.get(PassAPIClient.Endpoint.vault)

        guard let encryptedData = Data(base64Encoded: vaultResponse.encryptedData),
              let iv = Data(base64Encoded: vaultResponse.iv) else {
            throw PassError.invalidVaultData
        }

        let decryptedData = try decryptVaultData(encryptedData, iv: iv, using: key)

        let decryptedVault: PassVault
        do {
            decryptedVault = try JSONDecoder().decode(PassVault.self, from: decryptedData)
        } catch {
            Log.pass.error("Vault JSON decode failed after biometric unlock: \(String(describing: error), privacy: .public)")
            throw PassError.invalidVaultData
        }

        encryptionKey = key
        vault = decryptedVault
        serverVersion = vaultResponse.version
        hasVaultSetup = true

        // Save encrypted vault locally for AutoFill extension access
        let metadata = PassVaultMetadata(
            version: vaultResponse.version,
            iv: vaultResponse.iv,
            updatedAt: vaultResponse.updatedAt,
            lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        await saveVaultCache(encryptedData: encryptedData, metadata: metadata)

        // Register AutoFill QuickType suggestions
        await credentialService.updateCredentialIdentities(from: decryptedVault.items)

        // Pick up passkeys created by the AutoFill extension
        await mergePendingPasskeys()

        return true
    }

    /// Lock the vault (clear from memory)
    func lock() {
        encryptionKey = nil
        vault = nil
        serverVersion = 0
    }

    /// Lock and clear stored key (full sign out)
    func lockAndClearKey() {
        lock()
        // Security cleanup — a failed delete must be visible in logs
        do {
            try keychain.deleteBiometricProtected(for: KeychainService.Key.passEncryptionKey)
            try keychain.delete(for: KeychainService.Key.passSalt)
        } catch {
            Log.pass.fault("Failed to remove pass key material on sign-out: \(String(describing: error), privacy: .public)")
        }
        Task {
            do {
                try await vaultStore.clear()
            } catch {
                Log.pass.fault("Failed to remove vault cache on sign-out: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Disable biometric unlock (remove stored key from keychain)
    func disableBiometric() throws {
        try keychain.deleteBiometricProtected(for: KeychainService.Key.passEncryptionKey)
    }

    // MARK: - Read Operations (from in-memory vault)

    /// Get all items (excluding deleted)
    func getItems(type: PassVaultItemType? = nil) -> [PassVaultItem] {
        guard let vault = vault else { return [] }

        var items = vault.items.filter { $0.deletedAt == nil }

        if let type = type {
            items = items.filter { $0.type == type }
        }

        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Get items in trash
    func getTrashItems() -> [PassVaultItem] {
        guard let vault = vault else { return [] }
        return vault.items.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? 0) > ($1.deletedAt ?? 0) }
    }

    /// Get favorite items
    func getFavorites() -> [PassVaultItem] {
        guard let vault = vault else { return [] }
        return vault.items.filter { $0.favorite && $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Get item by ID
    func getItem(id: String) -> PassVaultItem? {
        vault?.items.first { $0.id == id }
    }

    /// Get all folders
    /// All folders in the vault
    var folders: [PassFolder] {
        vault?.folders ?? []
    }

    func getFolders() -> [PassFolder] {
        vault?.folders ?? []
    }

    /// Get items in a specific folder
    func getItemsInFolder(_ folderId: String?) -> [PassVaultItem] {
        guard let vault = vault else { return [] }
        return vault.items.filter { $0.folderId == folderId && $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Search items by name/username
    func searchItems(query: String) -> [PassVaultItem] {
        guard let vault = vault, !query.isEmpty else { return [] }
        let lowercasedQuery = query.lowercased()

        return vault.items.filter { item in
            guard item.deletedAt == nil else { return false }

            if item.name.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search username for password items
            if case .password(let passwordItem) = item {
                return passwordItem.username.lowercased().contains(lowercasedQuery)
            }

            return false
        }
    }

    /// Get items in trash (deleted but not permanently deleted)
    func getDeletedItems() -> [PassVaultItem] {
        guard let vault = vault else { return [] }
        return vault.items
            .filter { $0.deletedAt != nil }
            .sorted { $0.deletedAt ?? 0 > $1.deletedAt ?? 0 }
    }

    // MARK: - Item CRUD Operations

    /// Add a new item to the vault
    func addItem(_ item: PassVaultItem) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        vault.items.append(item)
        vault.lastModified = Int(Date().timeIntervalSince1970 * 1000)
        self.vault = vault

        try await saveVault()
    }

    /// Update an existing item in the vault
    func updateItem(_ item: PassVaultItem) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        guard let index = vault.items.firstIndex(where: { $0.id == item.id }) else {
            throw PassError.invalidVaultData
        }

        vault.items[index] = item
        vault.lastModified = Int(Date().timeIntervalSince1970 * 1000)
        self.vault = vault

        try await saveVault()
    }

    /// Soft delete an item (move to trash)
    func deleteItem(_ item: PassVaultItem) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        guard let index = vault.items.firstIndex(where: { $0.id == item.id }) else {
            throw PassError.invalidVaultData
        }

        let now = Int(Date().timeIntervalSince1970 * 1000)
        var updatedItem = vault.items[index]

        // Set deletedAt based on item type
        switch updatedItem {
        case .password(var passwordItem):
            passwordItem.deletedAt = now
            passwordItem.updatedAt = now
            updatedItem = .password(passwordItem)
        case .note(var noteItem):
            noteItem.deletedAt = now
            noteItem.updatedAt = now
            updatedItem = .note(noteItem)
        case .card(var cardItem):
            cardItem.deletedAt = now
            cardItem.updatedAt = now
            updatedItem = .card(cardItem)
        case .bankAccount(var bankItem):
            bankItem.deletedAt = now
            bankItem.updatedAt = now
            updatedItem = .bankAccount(bankItem)
        case .passkey(var passkeyItem):
            passkeyItem.deletedAt = now
            passkeyItem.updatedAt = now
            updatedItem = .passkey(passkeyItem)
        case .file(var fileItem):
            fileItem.deletedAt = now
            fileItem.updatedAt = now
            updatedItem = .file(fileItem)
        case .cryptoWallet(var walletItem):
            walletItem.deletedAt = now
            walletItem.updatedAt = now
            updatedItem = .cryptoWallet(walletItem)
        case .corrupted:
            break // Corrupted items can be deleted via permanentlyDeleteItem
        }

        vault.items[index] = updatedItem
        vault.lastModified = now
        self.vault = vault

        try await saveVault()
    }

    /// Restore an item from trash
    func restoreItem(_ item: PassVaultItem) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        guard let index = vault.items.firstIndex(where: { $0.id == item.id }) else {
            throw PassError.invalidVaultData
        }

        let now = Int(Date().timeIntervalSince1970 * 1000)
        var updatedItem = vault.items[index]

        // Clear deletedAt based on item type
        switch updatedItem {
        case .password(var passwordItem):
            passwordItem.deletedAt = nil
            passwordItem.updatedAt = now
            updatedItem = .password(passwordItem)
        case .note(var noteItem):
            noteItem.deletedAt = nil
            noteItem.updatedAt = now
            updatedItem = .note(noteItem)
        case .card(var cardItem):
            cardItem.deletedAt = nil
            cardItem.updatedAt = now
            updatedItem = .card(cardItem)
        case .bankAccount(var bankItem):
            bankItem.deletedAt = nil
            bankItem.updatedAt = now
            updatedItem = .bankAccount(bankItem)
        case .passkey(var passkeyItem):
            passkeyItem.deletedAt = nil
            passkeyItem.updatedAt = now
            updatedItem = .passkey(passkeyItem)
        case .file(var fileItem):
            fileItem.deletedAt = nil
            fileItem.updatedAt = now
            updatedItem = .file(fileItem)
        case .cryptoWallet(var walletItem):
            walletItem.deletedAt = nil
            walletItem.updatedAt = now
            updatedItem = .cryptoWallet(walletItem)
        case .corrupted:
            return // Corrupted items cannot be restored
        }

        vault.items[index] = updatedItem
        vault.lastModified = now
        self.vault = vault

        try await saveVault()
    }

    /// Permanently delete an item from the vault
    func permanentlyDeleteItem(_ item: PassVaultItem) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        vault.items.removeAll { $0.id == item.id }
        vault.lastModified = Int(Date().timeIntervalSince1970 * 1000)
        self.vault = vault

        try await saveVault()
    }

    /// Empty the trash (permanently delete all trashed items)
    func emptyTrash() async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        vault.items.removeAll { $0.deletedAt != nil }
        vault.lastModified = Int(Date().timeIntervalSince1970 * 1000)
        self.vault = vault

        try await saveVault()
    }

    /// Toggle favorite status for an item
    func toggleFavorite(_ item: PassVaultItem) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        guard let index = vault.items.firstIndex(where: { $0.id == item.id }) else {
            throw PassError.invalidVaultData
        }

        let now = Int(Date().timeIntervalSince1970 * 1000)
        var updatedItem = vault.items[index]

        switch updatedItem {
        case .password(var passwordItem):
            passwordItem.favorite = !(passwordItem.favorite ?? false)
            passwordItem.updatedAt = now
            updatedItem = .password(passwordItem)
        case .note(var noteItem):
            noteItem.favorite = !(noteItem.favorite ?? false)
            noteItem.updatedAt = now
            updatedItem = .note(noteItem)
        case .card(var cardItem):
            cardItem.favorite = !(cardItem.favorite ?? false)
            cardItem.updatedAt = now
            updatedItem = .card(cardItem)
        case .bankAccount(var bankItem):
            bankItem.favorite = !(bankItem.favorite ?? false)
            bankItem.updatedAt = now
            updatedItem = .bankAccount(bankItem)
        case .passkey(var passkeyItem):
            passkeyItem.favorite = !(passkeyItem.favorite ?? false)
            passkeyItem.updatedAt = now
            updatedItem = .passkey(passkeyItem)
        case .file(var fileItem):
            fileItem.favorite = !(fileItem.favorite ?? false)
            fileItem.updatedAt = now
            updatedItem = .file(fileItem)
        case .cryptoWallet(var walletItem):
            walletItem.favorite = !(walletItem.favorite ?? false)
            walletItem.updatedAt = now
            updatedItem = .cryptoWallet(walletItem)
        case .corrupted:
            return // Corrupted items cannot be favorited
        }

        vault.items[index] = updatedItem
        vault.lastModified = now
        self.vault = vault

        try await saveVault()
    }

    // MARK: - Folder Operations

    /// Add a new folder
    func addFolder(_ folder: PassFolder) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        vault.folders.append(folder)
        vault.lastModified = Int(Date().timeIntervalSince1970 * 1000)
        self.vault = vault

        try await saveVault()
    }

    /// Update a folder
    func updateFolder(_ folder: PassFolder) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        guard let index = vault.folders.firstIndex(where: { $0.id == folder.id }) else {
            throw PassError.invalidVaultData
        }

        vault.folders[index] = folder
        vault.lastModified = Int(Date().timeIntervalSince1970 * 1000)
        self.vault = vault

        try await saveVault()
    }

    /// Delete a folder (items in folder become root items)
    func deleteFolder(_ folder: PassFolder) async throws {
        guard var vault = vault else {
            throw PassError.noEncryptionKey
        }

        // Remove folder
        vault.folders.removeAll { $0.id == folder.id }

        // Move items in this folder to root (clear folderId)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        vault.items = vault.items.map { item in
            guard item.folderId == folder.id else { return item }

            var updatedItem = item
            switch updatedItem {
            case .password(var passwordItem):
                passwordItem.folderId = nil
                passwordItem.updatedAt = now
                updatedItem = .password(passwordItem)
            case .note(var noteItem):
                noteItem.folderId = nil
                noteItem.updatedAt = now
                updatedItem = .note(noteItem)
            case .card(var cardItem):
                cardItem.folderId = nil
                cardItem.updatedAt = now
                updatedItem = .card(cardItem)
            case .bankAccount(var bankItem):
                bankItem.folderId = nil
                bankItem.updatedAt = now
                updatedItem = .bankAccount(bankItem)
            case .passkey(var passkeyItem):
                passkeyItem.folderId = nil
                passkeyItem.updatedAt = now
                updatedItem = .passkey(passkeyItem)
            case .file(var fileItem):
                fileItem.folderId = nil
                fileItem.updatedAt = now
                updatedItem = .file(fileItem)
            case .cryptoWallet(var walletItem):
                walletItem.folderId = nil
                walletItem.updatedAt = now
                updatedItem = .cryptoWallet(walletItem)
            case .corrupted:
                break // Corrupted items don't have folder IDs
            }
            return updatedItem
        }

        vault.lastModified = now
        self.vault = vault

        try await saveVault()
    }

    // MARK: - Save Vault

    /// Encrypt and save vault to server
    private func saveVault() async throws {
        guard let key = encryptionKey, let vault = vault else {
            throw PassError.noEncryptionKey
        }

        isLoading = true
        defer { isLoading = false }

        // Encode vault to JSON
        let vaultData = try JSONEncoder().encode(vault)

        // Encrypt the vault
        let encryptedData = try crypto.encryptData(vaultData, using: key)

        // Split IV and ciphertext (encryptData returns IV + ciphertext + tag)
        let iv = encryptedData.prefix(12)
        let ciphertext = encryptedData.dropFirst(12)

        // Prepare update request
        let request = PassVaultUpdateRequest(
            encryptedData: ciphertext.base64EncodedString(),
            iv: iv.base64EncodedString(),
            expectedVersion: serverVersion
        )

        // Send to server
        let response: PassVaultResponse = try await api.put(PassAPIClient.Endpoint.vault, body: request)

        // Update server version
        serverVersion = response.version

        // Update local cache
        let metadata = PassVaultMetadata(
            version: response.version,
            iv: iv.base64EncodedString(),
            updatedAt: response.updatedAt,
            lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        try await vaultStore.saveVault(encryptedData: ciphertext, metadata: metadata)

        // Update AutoFill credential identities
        await credentialService.updateCredentialIdentities(from: vault.items)
    }

    // MARK: - Pending Passkeys (created by the AutoFill extension)

    /// Merge passkeys the AutoFill extension registered while the app wasn't running,
    /// push them to the server, then clear the pending queue.
    func mergePendingPasskeys() async {
        guard let key = encryptionKey, var vault = vault else { return }

        let pending: [SharedPassPasskeyItem]
        do {
            pending = try SharedPendingItemsStore.load(key: key)
        } catch {
            // Never clear an unreadable queue; already logged by the store
            Log.pass.error("Cannot read pending passkey queue: \(String(describing: error), privacy: .public)")
            return
        }
        guard !pending.isEmpty else { return }

        let existingCredentialIds = Set(vault.items.compactMap { item -> String? in
            guard case .passkey(let passkey) = item else { return nil }
            return passkey.credentialId
        })

        let now = Int(Date().timeIntervalSince1970 * 1000)
        var added = false

        for shared in pending where !existingCredentialIds.contains(shared.credentialId) {
            let item = PassPasskeyItem(
                id: shared.id,
                name: shared.name,
                rpId: shared.rpId,
                rpName: shared.rpName,
                credentialId: shared.credentialId,
                publicKey: shared.publicKey,
                privateKey: shared.privateKey,
                userHandle: shared.userHandle,
                userName: shared.userName,
                signCount: shared.signCount,
                createdAt: now,
                updatedAt: now
            )
            vault.items.append(.passkey(item))
            added = true
        }

        do {
            if added {
                vault.lastModified = now
                self.vault = vault
                try await saveVault()
                Log.pass.info("Merged \(pending.count) pending passkey(s) from AutoFill")
            }
            SharedPendingItemsStore.clear()
        } catch {
            // Keep the queue so the merge retries on the next unlock/sync —
            // but a persistent failure must be observable
            Log.pass.error("Failed to sync \(pending.count) pending passkey(s), will retry: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Sync

    /// Sync vault with server
    func sync() async throws {
        guard let key = encryptionKey else {
            throw PassError.noEncryptionKey
        }

        isLoading = true
        defer { isLoading = false }

        // Fetch latest from server
        let vaultResponse: PassVaultResponse = try await api.get(PassAPIClient.Endpoint.vault)

        guard let encryptedData = Data(base64Encoded: vaultResponse.encryptedData),
              let iv = Data(base64Encoded: vaultResponse.iv) else {
            throw PassError.invalidVaultData
        }

        let decryptedData = try decryptVaultData(encryptedData, iv: iv, using: key)

        let serverVault: PassVault
        do {
            serverVault = try JSONDecoder().decode(PassVault.self, from: decryptedData)
        } catch {
            Log.pass.error("Vault JSON decode failed during sync: \(String(describing: error), privacy: .public)")
            throw PassError.invalidVaultData
        }

        // Update local state
        vault = serverVault
        serverVersion = vaultResponse.version

        // Update local cache
        let metadata = PassVaultMetadata(
            version: vaultResponse.version,
            iv: vaultResponse.iv,
            updatedAt: vaultResponse.updatedAt,
            lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        try await vaultStore.saveVault(encryptedData: encryptedData, metadata: metadata)

        // Update AutoFill credential identities
        await credentialService.updateCredentialIdentities(from: serverVault.items)
    }

    // MARK: - Private Helpers

    private func storeKeyInKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        do {
            try keychain.saveBiometricProtected(keyData, for: KeychainService.Key.passEncryptionKey)
        } catch {
            // Without this, "Unlock with Face ID" silently never appears
            Log.pass.error("Failed to store biometric-protected key: \(String(describing: error), privacy: .public)")
        }
    }

    private func decryptVaultData(_ encryptedData: Data, iv: Data, using key: SymmetricKey) throws -> Data {
        // Reconstruct combined data for AES-GCM: IV + ciphertext + tag
        var combined = iv
        combined.append(encryptedData)

        return try crypto.decryptData(combined, using: key)
    }

    // MARK: - Clipboard

    /// Copy text to clipboard with auto-clear
    func copyToClipboard(_ text: String, clearAfter seconds: TimeInterval = 30) {
        UIPasteboard.general.string = text

        // Schedule clipboard clear
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if UIPasteboard.general.string == text {
                UIPasteboard.general.string = ""
            }
        }
    }
}

// MARK: - PassAPIClient

/// Dedicated API client for Pass service
actor PassAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenProvider: @Sendable () async throws -> String
    private let forceRefresh: @Sendable () async throws -> String

    init(
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized }
    ) {
        self.baseURL = Config.passAPIBaseURL
        self.tokenProvider = tokenProvider
        self.forceRefresh = forceRefresh
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Request Building

    private func buildRequest(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = try await tokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = body
        return request
    }

    /// Runs `operation` once; on `APIError.unauthorized` forces exactly one token
    /// refresh and retries `operation` once more. A second `401` (or any other
    /// error from the retry) propagates as-is — no further retries.
    private func withUnauthorizedRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch APIError.unauthorized {
            _ = try await forceRefresh()
            return try await operation()
        }
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await withUnauthorizedRetry {
            let request = try await buildRequest(path: path, method: "GET")
            return try await perform(request)
        }
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await withUnauthorizedRetry {
            let bodyData = try encoder.encode(body)
            let request = try await buildRequest(path: path, method: "POST", body: bodyData)
            return try await perform(request)
        }
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await withUnauthorizedRetry {
            let bodyData = try encoder.encode(body)
            let request = try await buildRequest(path: path, method: "PUT", body: bodyData)
            return try await perform(request)
        }
    }

    // MARK: - Request Execution

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            if httpResponse.statusCode == 409 {
                // Version conflict
                throw APIError.httpError(statusCode: 409, message: "VERSION_CONFLICT")
            }
            let message = try? decoder.decode([String: String].self, from: data)["error"]
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - Endpoints

    enum Endpoint {
        static let keyInfo = "/v1/vault/key-info"
        static let vault = "/v1/vault"
        static let vaultSetup = "/v1/vault/setup"
        static let vaultVersion = "/v1/vault/version"
        static let files = "/v1/files"
        static let audit = "/v1/audit"

        static func file(_ fileId: String) -> String {
            "/v1/files/\(fileId)"
        }
    }
}
