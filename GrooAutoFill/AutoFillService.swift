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
import os

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
            return "Authentication failed. Try again."
        case .decryptionFailed:
            return "Couldn't decrypt the vault. Open the Groo app to re-sync."
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
    @Published var passkeys: [SharedPassPasskeyItem] = []
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
        } catch SharedKeychainError.itemNotFound {
            // Key was never shared to the app group — setup issue, not a locked vault
            Log.autofill.error("Encryption key not found in shared keychain")
            throw AutoFillError.vaultNotSetup
        } catch {
            Log.autofill.error("Failed to load encryption key: \(String(describing: error), privacy: .public)")
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
            // Key mismatch vs corrupt data are different bugs — keep the cause
            Log.autofill.error("Vault decryption failed: \(String(describing: error), privacy: .public)")
            throw AutoFillError.decryptionFailed
        }

        // Parse vault
        guard let vaultData = vaultJson.data(using: .utf8) else {
            Log.autofill.error("Decrypted vault is not valid UTF-8")
            throw AutoFillError.decryptionFailed
        }

        let vault: SharedPassVault
        do {
            vault = try JSONDecoder().decode(SharedPassVault.self, from: vaultData)
        } catch {
            // Schema mismatch, not a crypto failure
            Log.autofill.error("Vault JSON decode failed: \(String(describing: error), privacy: .public)")
            throw error
        }

        // Extract password items (non-deleted only)
        credentials = vault.items.compactMap { item -> SharedPassPasswordItem? in
            guard let passwordItem = item.passwordItem, !passwordItem.isDeleted else {
                return nil
            }
            return passwordItem
        }

        // Extract passkey items (non-deleted only)
        passkeys = vault.items.compactMap { item -> SharedPassPasskeyItem? in
            guard let passkeyItem = item.passkeyItem, !passkeyItem.isDeleted else {
                return nil
            }
            return passkeyItem
        }

        // Merge passkeys created here but not yet synced into the vault by the main app
        do {
            let knownCredentialIds = Set(passkeys.map(\.credentialId))
            let pending = try SharedPendingItemsStore.load(key: key)
            passkeys.append(contentsOf: pending.filter { !knownCredentialIds.contains($0.credentialId) })
        } catch {
            // Don't fail the whole unlock over the queue; already logged by the store
            Log.autofill.error("Skipping pending passkeys: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Passkey Registration

    /// Persist a newly registered passkey to the pending queue for the main app to sync
    func savePendingPasskey(_ item: SharedPassPasskeyItem) throws {
        guard let key = encryptionKey else {
            throw AutoFillError.vaultLocked
        }
        try SharedPendingItemsStore.append(item, key: key)
        passkeys.append(item)
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

        // Filter credentials that match any of the domains (checks all URLs)
        return credentials.filter { credential in
            let credentialDomains = credential.domains
            guard !credentialDomains.isEmpty else { return false }

            return searchDomains.contains { searchDomain in
                credentialDomains.contains { credDomain in
                    Self.domainsMatch(credDomain, searchDomain)
                }
            }
        }
    }

    /// Exact host or subdomain match: "accounts.google.com" matches a saved
    /// "google.com" (and vice versa), but "app.com" never matches "myapp.com"
    static func domainsMatch(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
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

    // MARK: - Passkey Methods

    /// Find a passkey by its credential ID
    func findPasskey(credentialId: Data) -> SharedPassPasskeyItem? {
        // Stored credentialId is base64url-encoded, so compare in same format
        let credentialIdBase64URL = credentialId.base64URLEncodedString
        return passkeys.first { $0.credentialId == credentialIdBase64URL }
    }

    /// Filter passkeys by relying party ID and the request's allowed credential list
    func filteredPasskeys(for rpId: String?, allowedCredentialIds: [Data] = []) -> [SharedPassPasskeyItem] {
        guard let rpId = rpId else { return [] }

        let allowed = Set(allowedCredentialIds.map { $0.base64URLEncodedString })
        return passkeys.filter { passkey in
            passkey.rpId == rpId && (allowed.isEmpty || allowed.contains(passkey.credentialId))
        }
    }

    /// Search passkeys by query string
    func searchPasskeys(query: String) -> [SharedPassPasskeyItem] {
        guard !query.isEmpty else {
            return passkeys
        }

        let lowercasedQuery = query.lowercased()

        return passkeys.filter { passkey in
            passkey.name.lowercased().contains(lowercasedQuery) ||
            passkey.userName.lowercased().contains(lowercasedQuery) ||
            passkey.rpId.lowercased().contains(lowercasedQuery)
        }
    }
}
