//
//  PassVaultStore.swift
//  Groo
//
//  File-based storage for encrypted Pass vault in App Group container.
//  Stores the encrypted vault blob separately from metadata for efficiency.
//

import Foundation

// MARK: - Vault Metadata

/// Metadata about the stored vault (stored as JSON)
struct PassVaultMetadata: Codable {
    let version: Int           // Server version for optimistic locking
    let iv: String             // IV used for encryption
    let updatedAt: Int         // Server timestamp
    var lastSyncedAt: Int      // Local sync timestamp
}

// MARK: - PassVaultStore

/// Actor-based storage for Pass vault files
/// Uses App Group container for extension sharing
actor PassVaultStore {
    private let fileManager = FileManager.default

    /// App Group container URL
    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier)
    }

    /// Pass vault directory within App Group
    private var passDirectoryURL: URL? {
        containerURL?.appendingPathComponent("pass", isDirectory: true)
    }

    /// Encrypted vault data file
    private var vaultDataURL: URL? {
        passDirectoryURL?.appendingPathComponent("vault.enc")
    }

    /// Vault metadata file
    private var vaultMetadataURL: URL? {
        passDirectoryURL?.appendingPathComponent("vault.meta.json")
    }

    // MARK: - Directory Setup

    /// Ensure the pass directory exists
    private func ensureDirectoryExists() throws {
        guard let directoryURL = passDirectoryURL else {
            throw PassVaultStoreError.containerNotAvailable
        }

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save Operations

    /// Save encrypted vault data and metadata
    func saveVault(encryptedData: Data, metadata: PassVaultMetadata) throws {
        try ensureDirectoryExists()

        guard let dataURL = vaultDataURL, let metaURL = vaultMetadataURL else {
            throw PassVaultStoreError.containerNotAvailable
        }

        // Write encrypted data
        try encryptedData.write(to: dataURL, options: .atomic)

        // Write metadata
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metaURL, options: .atomic)
    }

    /// Update only the metadata (e.g., after sync)
    func updateMetadata(_ metadata: PassVaultMetadata) throws {
        guard let metaURL = vaultMetadataURL else {
            throw PassVaultStoreError.containerNotAvailable
        }

        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metaURL, options: .atomic)
    }

    // MARK: - Load Operations

    /// Load encrypted vault data and metadata
    func loadVault() throws -> (data: Data, metadata: PassVaultMetadata)? {
        guard let dataURL = vaultDataURL, let metaURL = vaultMetadataURL else {
            throw PassVaultStoreError.containerNotAvailable
        }

        // Check if vault exists
        guard fileManager.fileExists(atPath: dataURL.path),
              fileManager.fileExists(atPath: metaURL.path) else {
            return nil
        }

        // Read encrypted data
        let encryptedData = try Data(contentsOf: dataURL)

        // Read metadata
        let metadataData = try Data(contentsOf: metaURL)
        let metadata = try JSONDecoder().decode(PassVaultMetadata.self, from: metadataData)

        return (encryptedData, metadata)
    }

    /// Load only metadata (for quick version checks)
    func loadMetadata() throws -> PassVaultMetadata? {
        guard let metaURL = vaultMetadataURL else {
            throw PassVaultStoreError.containerNotAvailable
        }

        guard fileManager.fileExists(atPath: metaURL.path) else {
            return nil
        }

        let metadataData = try Data(contentsOf: metaURL)
        return try JSONDecoder().decode(PassVaultMetadata.self, from: metadataData)
    }

    /// Check if vault exists locally
    func vaultExists() -> Bool {
        guard let dataURL = vaultDataURL else { return false }
        return fileManager.fileExists(atPath: dataURL.path)
    }

    // MARK: - Delete Operations

    /// Clear all vault data (for sign out)
    func clear() throws {
        guard let directoryURL = passDirectoryURL else {
            return  // Nothing to clear if container not available
        }

        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
    }
}

// MARK: - Errors

enum PassVaultStoreError: Error, LocalizedError {
    case containerNotAvailable
    case vaultNotFound
    case metadataNotFound

    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "App Group container is not available"
        case .vaultNotFound:
            return "Vault data not found"
        case .metadataNotFound:
            return "Vault metadata not found"
        }
    }
}
