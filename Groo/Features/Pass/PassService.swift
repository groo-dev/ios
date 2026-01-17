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
    private let keychain: KeychainService
    private let vaultStore: PassVaultStore

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
        keychain: KeychainService = KeychainService(),
        vaultStore: PassVaultStore = PassVaultStore()
    ) {
        self.api = api ?? PassAPIClient(keychain: keychain)
        self.crypto = crypto
        self.keychain = keychain
        self.vaultStore = vaultStore
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
        } catch {
            // 404 means no vault setup yet
            hasVaultSetup = false
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

        // Derive encryption key
        let key = try crypto.deriveKey(password: password, salt: salt)

        // Fetch and decrypt vault to verify password
        let vaultResponse: PassVaultResponse = try await api.get(PassAPIClient.Endpoint.vault)

        guard let encryptedData = Data(base64Encoded: vaultResponse.encryptedData),
              let iv = Data(base64Encoded: vaultResponse.iv) else {
            throw PassError.invalidVaultData
        }

        // Decrypt vault
        let decryptedData = try decryptVaultData(encryptedData, iv: iv, using: key)

        guard let decryptedVault = try? JSONDecoder().decode(PassVault.self, from: decryptedData) else {
            throw PassError.decryptionFailed
        }

        // Success - store key and vault
        encryptionKey = key
        vault = decryptedVault
        serverVersion = vaultResponse.version
        hasVaultSetup = true

        // Store key in Keychain with biometric protection
        storeKeyInKeychain(key)

        // Store salt for biometric unlock
        try? keychain.save(salt, for: KeychainService.Key.passSalt)

        // Save encrypted vault locally
        let metadata = PassVaultMetadata(
            version: vaultResponse.version,
            iv: vaultResponse.iv,
            updatedAt: vaultResponse.updatedAt,
            lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        try? await vaultStore.saveVault(encryptedData: encryptedData, metadata: metadata)

        return true
    }

    /// Unlock using biometric authentication
    func unlockWithBiometric() async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        // Load key from Keychain (triggers Face ID/Touch ID)
        let keyData = try keychain.loadBiometricProtected(
            for: KeychainService.Key.passEncryptionKey,
            prompt: "Authenticate to unlock Pass"
        )
        let key = SymmetricKey(data: keyData)

        // Load salt
        guard let salt = try? keychain.load(for: KeychainService.Key.passSalt) else {
            throw PassError.vaultNotSetup
        }
        keySalt = salt

        // Try to load from local cache first
        if let cached = try? await vaultStore.loadVault() {
            let decryptedData = try decryptVaultData(
                cached.data,
                iv: Data(base64Encoded: cached.metadata.iv) ?? Data(),
                using: key
            )

            if let decryptedVault = try? JSONDecoder().decode(PassVault.self, from: decryptedData) {
                encryptionKey = key
                vault = decryptedVault
                serverVersion = cached.metadata.version
                hasVaultSetup = true

                // Sync in background
                Task {
                    try? await sync()
                }

                return true
            }
        }

        // Fallback to server fetch
        let vaultResponse: PassVaultResponse = try await api.get(PassAPIClient.Endpoint.vault)

        guard let encryptedData = Data(base64Encoded: vaultResponse.encryptedData),
              let iv = Data(base64Encoded: vaultResponse.iv) else {
            throw PassError.invalidVaultData
        }

        let decryptedData = try decryptVaultData(encryptedData, iv: iv, using: key)

        guard let decryptedVault = try? JSONDecoder().decode(PassVault.self, from: decryptedData) else {
            throw PassError.decryptionFailed
        }

        encryptionKey = key
        vault = decryptedVault
        serverVersion = vaultResponse.version
        hasVaultSetup = true

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
        try? keychain.deleteBiometricProtected(for: KeychainService.Key.passEncryptionKey)
        try? keychain.delete(for: KeychainService.Key.passSalt)
        Task {
            try? await vaultStore.clear()
        }
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

        guard let serverVault = try? JSONDecoder().decode(PassVault.self, from: decryptedData) else {
            throw PassError.decryptionFailed
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
    }

    // MARK: - Private Helpers

    private func storeKeyInKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        try? keychain.saveBiometricProtected(keyData, for: KeychainService.Key.passEncryptionKey)
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
    private let keychain: KeychainService
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(keychain: KeychainService = KeychainService()) {
        self.baseURL = Config.passAPIBaseURL
        self.keychain = keychain
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - PAT Token

    private func getPatToken() -> String? {
        try? keychain.loadString(for: KeychainService.Key.patToken)
    }

    // MARK: - Request Building

    private func buildRequest(
        path: String,
        method: String,
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = getPatToken() {
            request.setValue("session=\(token)", forHTTPHeaderField: "Cookie")
        }

        request.httpBody = body
        return request
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "POST", body: bodyData)
        return try await perform(request)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "PUT", body: bodyData)
        return try await perform(request)
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
