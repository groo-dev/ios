//
//  SharedVaultStore.swift
//  Groo
//
//  Shared vault storage access for app and extensions.
//  Reads encrypted vault from App Group container.
//

import Foundation

/// Metadata about the stored vault
struct SharedVaultMetadata: Codable {
    let version: Int
    let iv: String
    let updatedAt: Int
    var lastSyncedAt: Int
}

enum SharedVaultStoreError: Error {
    case containerNotAvailable
    case vaultNotFound
}

enum SharedVaultStore {
    private static let fileManager = FileManager.default

    /// Test seam: when set, vault files are read from under this directory
    /// instead of the App Group container. Production never sets this.
    nonisolated(unsafe) static var overrideDirectoryURL: URL?

    /// App Group container URL
    private static var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)
    }

    /// Pass vault directory within App Group (or the injected override)
    private static var passDirectoryURL: URL? {
        if let overrideDirectoryURL {
            return overrideDirectoryURL.appendingPathComponent("pass", isDirectory: true)
        }
        return containerURL?.appendingPathComponent("pass", isDirectory: true)
    }

    /// Encrypted vault data file
    private static var vaultDataURL: URL? {
        passDirectoryURL?.appendingPathComponent("vault.enc")
    }

    /// Vault metadata file
    private static var vaultMetadataURL: URL? {
        passDirectoryURL?.appendingPathComponent("vault.meta.json")
    }

    /// Load encrypted vault data and metadata
    static func loadVault() throws -> (data: Data, metadata: SharedVaultMetadata) {
        guard let dataURL = vaultDataURL, let metaURL = vaultMetadataURL else {
            throw SharedVaultStoreError.containerNotAvailable
        }

        guard fileManager.fileExists(atPath: dataURL.path),
              fileManager.fileExists(atPath: metaURL.path) else {
            throw SharedVaultStoreError.vaultNotFound
        }

        let encryptedData = try Data(contentsOf: dataURL)
        let metadataData = try Data(contentsOf: metaURL)
        let metadata = try JSONDecoder().decode(SharedVaultMetadata.self, from: metadataData)

        return (encryptedData, metadata)
    }

    /// Check if vault exists locally
    static func vaultExists() -> Bool {
        guard let dataURL = vaultDataURL else { return false }
        return fileManager.fileExists(atPath: dataURL.path)
    }
}
