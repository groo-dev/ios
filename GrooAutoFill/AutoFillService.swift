//
//  AutoFillService.swift
//  GrooAutoFill
//
//  Service for loading and managing credentials in the AutoFill extension.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation

enum AutoFillError: Error, LocalizedError {
    case vaultNotSetup
    case vaultLocked
    case decryptionFailed
    case noCredentialsFound

    var errorDescription: String? {
        switch self {
        case .vaultNotSetup:
            return "Please set up Groo Pass in the main app first"
        case .vaultLocked:
            return "Vault is locked. Please unlock in the main app"
        case .decryptionFailed:
            return "Failed to decrypt vault"
        case .noCredentialsFound:
            return "No matching credentials found"
        }
    }
}

@MainActor
class AutoFillService: ObservableObject {
    @Published var isLoading = false
    @Published var isUnlocked = false
    @Published var credentials: [SharedPassPasswordItem] = []
    @Published var error: String?

    private var encryptionKey: SymmetricKey?

    // MARK: - Vault Status

    var hasVault: Bool {
        SharedVaultStore.vaultExists() && SharedKeychain.encryptionKeyExists()
    }

    // MARK: - Unlock

    /// Unlock the vault using biometric authentication
    func unlock() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Check if vault exists
        guard SharedVaultStore.vaultExists() else {
            throw AutoFillError.vaultNotSetup
        }

        // Load encryption key with biometric auth
        do {
            encryptionKey = try SharedKeychain.loadEncryptionKey(prompt: "Authenticate to access passwords")
        } catch {
            throw AutoFillError.vaultLocked
        }

        // Load and decrypt vault
        try await loadCredentials()

        isUnlocked = true
    }

    // MARK: - Load Credentials

    private func loadCredentials() async throws {
        guard let key = encryptionKey else {
            throw AutoFillError.vaultLocked
        }

        // Load encrypted vault
        let (encryptedData, metadata) = try SharedVaultStore.loadVault()

        // Decrypt vault
        let vaultJson: String
        do {
            vaultJson = try SharedCrypto.decryptVault(
                encryptedData: encryptedData,
                iv: metadata.iv,
                key: key
            )
        } catch {
            throw AutoFillError.decryptionFailed
        }

        // Parse vault
        guard let vaultData = vaultJson.data(using: .utf8) else {
            throw AutoFillError.decryptionFailed
        }

        let vault = try JSONDecoder().decode(SharedPassVault.self, from: vaultData)

        // Extract password items (non-deleted only)
        credentials = vault.items.compactMap { item -> SharedPassPasswordItem? in
            guard let passwordItem = item.passwordItem, !passwordItem.isDeleted else {
                return nil
            }
            return passwordItem
        }
    }

    // MARK: - Search

    /// Filter credentials by service identifiers (domains)
    func filteredCredentials(for serviceIdentifiers: [ASCredentialServiceIdentifier]) -> [SharedPassPasswordItem] {
        guard !serviceIdentifiers.isEmpty else {
            return credentials
        }

        // Extract domains from service identifiers
        let searchDomains = serviceIdentifiers.compactMap { identifier -> String? in
            switch identifier.type {
            case .domain:
                return identifier.identifier.lowercased()
            case .URL:
                guard let url = URL(string: identifier.identifier),
                      let host = url.host else {
                    return nil
                }
                return host.lowercased()
            @unknown default:
                return nil
            }
        }

        guard !searchDomains.isEmpty else {
            return credentials
        }

        // Filter credentials that match any of the domains
        return credentials.filter { credential in
            guard let credentialDomain = credential.primaryDomain else {
                return false
            }

            return searchDomains.contains { searchDomain in
                // Match if either contains the other (handles subdomains)
                credentialDomain.contains(searchDomain) ||
                searchDomain.contains(credentialDomain)
            }
        }
    }

    /// Search credentials by query string
    func searchCredentials(query: String) -> [SharedPassPasswordItem] {
        guard !query.isEmpty else {
            return credentials
        }

        let lowercasedQuery = query.lowercased()

        return credentials.filter { credential in
            credential.name.lowercased().contains(lowercasedQuery) ||
            credential.username.lowercased().contains(lowercasedQuery) ||
            credential.urls.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
}
