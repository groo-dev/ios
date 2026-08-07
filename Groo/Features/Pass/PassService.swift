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
    private let credentialService: any CredentialIdentityProviding
    private let pendingPasskeys: any PendingPasskeyStoring

    // Encryption state
    private var encryptionKey: SymmetricKey?
    private var keySalt: Data?
    private var kdfIterations: UInt32 = 600_000

    // Cached decrypted vault (in-memory only)
    private var vault: PassVault?
    private var serverVersion: Int = 0

    /// Which storage the server says is authoritative: 1 = the legacy blob,
    /// 2 = per-item records. iOS never converts — only the web app does — so
    /// this is read and followed, never written.
    private(set) var formatVersion: Int = 1
    private var recordState: PassRecordState = .empty

    // State
    private(set) var hasVaultSetup = false
    private(set) var isLoading = false
    private(set) var lastError: String?

    init(
        api: PassAPIClient? = nil,
        crypto: CryptoService = CryptoService(),
        keychain: any KeychainServicing = KeychainService(),
        vaultStore: PassVaultStore = PassVaultStore(),
        credentialService: any CredentialIdentityProviding = CredentialIdentityService(),
        pendingPasskeys: any PendingPasskeyStoring = SharedPendingPasskeyStore(),
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized }
    ) {
        self.api = api ?? PassAPIClient(tokenProvider: tokenProvider, forceRefresh: forceRefresh)
        self.crypto = crypto
        self.keychain = keychain
        self.vaultStore = vaultStore
        self.credentialService = credentialService
        self.pendingPasskeys = pendingPasskeys
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

        // Derive the wrapping key, then unwrap the vault key. Unwrapping IS the
        // password check — it fails on 32 bytes, before any vault fetch.
        let wrappingKey = try crypto.deriveKey(
            password: password,
            salt: salt,
            iterations: kdfIterations
        )
        let key = try crypto.unwrapKey(
            EncryptedPayload(
                ciphertext: keyInfo.wrappedVaultKey,
                iv: keyInfo.wrapIv,
                version: 1
            ),
            using: wrappingKey
        )

        formatVersion = keyInfo.formatVersion ?? 1

        let decryptedVault: PassVault
        if formatVersion == 2 {
            // Records are authoritative; the blob endpoint 410s now.
            encryptionKey = key
            recordState = .empty
            decryptedVault = try await loadFromRecords(using: key)
        } else {
            let vaultResponse: PassVaultResponse
            do {
                vaultResponse = try await api.get(PassAPIClient.Endpoint.vault)
            } catch APIError.httpError(let status, let code)
                        where status == 410 || code == "FORMAT_MIGRATED" {
                // The vault was converted on the web app between our key-info
                // read and this fetch. This build speaks records, so recover by
                // switching rather than surfacing an error — "update required"
                // is for builds that predate record support, not this one.
                Log.pass.info("Vault converted to per-item records; switching")
                formatVersion = 2
                encryptionKey = key
                recordState = .empty
                let assembled = try await loadFromRecords(using: key)
                storeKeyInKeychain(key)
                try? keychain.save(salt, for: KeychainService.Key.passSalt)
                await credentialService.updateCredentialIdentities(from: assembled.items)
                await mergePendingPasskeys()
                return true
            }

            guard let encryptedData = Data(base64Encoded: vaultResponse.encryptedData),
                  let iv = Data(base64Encoded: vaultResponse.iv) else {
                throw PassError.invalidVaultData
            }

            let decryptedData = try decryptVaultData(encryptedData, iv: iv, using: key)

            // Decryption succeeded, so a decode failure is a schema bug — not a wrong password
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

            let metadata = PassVaultMetadata(
                version: vaultResponse.version,
                iv: vaultResponse.iv,
                updatedAt: vaultResponse.updatedAt,
                lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
            )
            await saveVaultCache(encryptedData: encryptedData, metadata: metadata)
        }

        // Store key in Keychain with biometric protection
        storeKeyInKeychain(key)

        // Store salt for biometric unlock
        do {
            try keychain.save(salt, for: KeychainService.Key.passSalt)
        } catch {
            // Biometric unlock will throw vaultNotSetup later without this salt
            Log.pass.error("Failed to store pass salt: \(String(describing: error), privacy: .public)")
        }

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

        // Fallback to server fetch. Branch on the server's format first: the
        // blob endpoint 410s once records are authoritative, and treating that
        // as a network error would leave a stale enrolment quietly in place.
        let fallbackKeyInfo: PassKeyInfo = try await api.get(PassAPIClient.Endpoint.keyInfo)
        formatVersion = fallbackKeyInfo.formatVersion ?? 1

        if formatVersion == 2 {
            encryptionKey = key
            recordState = .empty
            let assembled = try await loadFromRecords(using: key)
            await credentialService.updateCredentialIdentities(from: assembled.items)
            await mergePendingPasskeys()
            return true
        }

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
        // Decrypted records are as sensitive as the key that opened them.
        recordState = .empty
        formatVersion = 1
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

    // MARK: - Per-item records

    /// Pull records, rebuild the in-memory vault, and refresh the AutoFill cache.
    ///
    /// Returns the assembled vault so callers can reuse it without re-reading
    /// `self.vault`.
    @discardableResult
    private func loadFromRecords(using key: SymmetricKey) async throws -> PassVault {
        recordState = try await PassRecordSync.pull(from: recordState, vaultKey: key) { since in
            try await api.get(PassAPIClient.Endpoint.recordsSince(since))
        }

        // The sharing private key lives in its own column, not in a record.
        // Absent is a normal state (an account that has never shared).
        var rsaPrivateKey: String?
        do {
            let stored: SharedPrivateKeyResponse = try await api.get(
                PassAPIClient.Endpoint.privateKey
            )
            if let ciphertext = Data(base64Encoded: stored.encryptedPrivateKey),
               let iv = Data(base64Encoded: stored.privateKeyIv) {
                rsaPrivateKey = String(
                    data: try decryptVaultData(ciphertext, iv: iv, using: key),
                    encoding: .utf8
                )
            }
        } catch APIError.httpError(let status, _) where status == 404 {
            rsaPrivateKey = nil
        }

        let assembled = try PassRecordSync.buildVault(from: recordState, rsaPrivateKey: rsaPrivateKey)
        vault = assembled
        // The cursor doubles as the version for freshness comparisons.
        serverVersion = recordState.cursor
        hasVaultSetup = true

        await refreshVaultCache(assembled, using: key)
        return assembled
    }

    /// Re-encrypt the assembled vault into the App Group cache.
    ///
    /// The cache deliberately stays a single blob even in records mode: it is a
    /// local, read-only cache for AutoFill, not a sync artifact, so AutoFill's
    /// read path needs no changes. Regenerating it is local-only work.
    private func refreshVaultCache(_ vault: PassVault, using key: SymmetricKey) async {
        do {
            let encoded = try JSONEncoder().encode(vault)
            let sealed = try crypto.encryptData(encoded, using: key)
            let iv = sealed.prefix(12)
            let ciphertext = sealed.dropFirst(12)
            let metadata = PassVaultMetadata(
                version: serverVersion,
                iv: iv.base64EncodedString(),
                updatedAt: Int(Date().timeIntervalSince1970 * 1000),
                lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
            )
            try await vaultStore.saveVault(encryptedData: ciphertext, metadata: metadata)
        } catch {
            // A silent failure here means AutoFill serves stale credentials.
            Log.pass.error("Failed to refresh vault cache from records: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Save Vault

    /// Persist the current vault.
    ///
    /// At format 1 this is the whole-blob PUT it always was. At format 2 it
    /// diffs the in-memory vault against the last synced records and writes only
    /// what changed, so all eleven existing call sites keep working unchanged.
    private func saveVault() async throws {
        guard let key = encryptionKey, let vault = vault else {
            throw PassError.noEncryptionKey
        }

        if formatVersion == 2 {
            try await saveChangedRecords(vault, using: key)
            return
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


    /// Write only the records whose payload actually changed.
    ///
    /// Trash is an update (the item keeps its record, with `deletedAt` set) —
    /// the server must never learn what was thrown away. Only an item that has
    /// left the vault entirely becomes a tombstone.
    ///
    /// Caveat, inherited rather than introduced: an item is re-encoded from its
    /// typed model, so a field this build does not model is dropped from the
    /// item it rewrites. The blob path already did this to *every* item on
    /// every save; per-record writes narrow the blast radius to the items that
    /// actually changed.
    private func saveChangedRecords(_ vault: PassVault, using key: SymmetricKey) async throws {
        isLoading = true
        defer { isLoading = false }

        var live = Set<String>()

        for item in vault.items {
            live.insert(item.id)
            let payload = try JSONEncoder().encode(item)
            try await writeRecordIfChanged(id: item.id, kind: .item, payload: payload, using: key)
        }
        for folder in vault.folders {
            live.insert(folder.id)
            let payload = try JSONEncoder().encode(folder)
            try await writeRecordIfChanged(id: folder.id, kind: .folder, payload: payload, using: key)
        }

        // Anything the vault no longer holds was permanently deleted.
        for id in recordState.records.keys where !live.contains(id) {
            let _: SharedRecordDeleteResponse = try await api.delete(
                PassAPIClient.Endpoint.record(id)
            )
            recordState.records.removeValue(forKey: id)
        }

        await credentialService.updateCredentialIdentities(from: vault.items)
        await refreshVaultCache(vault, using: key)
    }

    private func writeRecordIfChanged(
        id: String,
        kind: SharedRecordKind,
        payload: Data,
        using key: SymmetricKey
    ) async throws {
        let existing = recordState.records[id]
        if let existing, normalized(existing.data) == normalized(payload) {
            return
        }

        let request = try SharedRecordCrypto.encryptRecord(
            id: id, kind: kind, payload: payload, vaultKey: key
        )

        let response: SharedRecordWriteResponse
        if let existing {
            var update = request
            update.expectedVersion = existing.version
            do {
                response = try await api.put(PassAPIClient.Endpoint.record(id), body: update)
            } catch APIError.recordConflict(let current) {
                // Someone else wrote this record first. Re-apply our payload on
                // top of the server's version and retry exactly once; a second
                // conflict surfaces rather than looping.
                var retry = request
                retry.expectedVersion = current.version
                response = try await api.put(PassAPIClient.Endpoint.record(id), body: retry)
            }
        } else {
            response = try await api.post(PassAPIClient.Endpoint.records, body: request)
        }

        recordState.records[id] = PassDecodedRecord(
            id: id, kind: kind, data: payload,
            version: response.version, seq: response.seq
        )
        recordState.cursor = max(recordState.cursor, response.seq)
        serverVersion = recordState.cursor
    }

    /// Key-order-independent comparison, so a re-encode that only reorders keys
    /// is not mistaken for a change and does not rewrite the whole vault.
    private func normalized(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: - Pending Passkeys (created by the AutoFill extension)

    /// Merge passkeys the AutoFill extension registered while the app wasn't running,
    /// push them to the server, then clear the pending queue.
    func mergePendingPasskeys() async {
        guard let key = encryptionKey, var vault = vault else { return }

        let pending: [SharedPassPasskeyItem]
        do {
            pending = try pendingPasskeys.load(key: key)
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
            pendingPasskeys.clear()
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

        if formatVersion == 2 {
            let assembled = try await loadFromRecords(using: key)
            await credentialService.updateCredentialIdentities(from: assembled.items)
            // Last, so the merge applies on top of what was just synced.
            await mergePendingPasskeys()
            return
        }

        // Fetch latest from server
        let vaultResponse: PassVaultResponse
        do {
            vaultResponse = try await api.get(PassAPIClient.Endpoint.vault)
        } catch APIError.httpError(let status, let code)
                    where status == 410 || code == "FORMAT_MIGRATED" {
            // Converted elsewhere while we were running; switch and resync.
            Log.pass.info("Vault converted to per-item records; switching on sync")
            formatVersion = 2
            recordState = .empty
            let assembled = try await loadFromRecords(using: key)
            await credentialService.updateCredentialIdentities(from: assembled.items)
            await mergePendingPasskeys()
            return
        }

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

        // Drain passkeys the AutoFill extension queued. Runs last so the merge
        // applies on top of the vault/serverVersion just fetched, keeping its
        // PUT's expectedVersion current. Without this the queue only drained on
        // unlock, which — since the app never re-locks on background — meant a
        // cold start.
        await mergePendingPasskeys()
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
