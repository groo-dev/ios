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
            let pending = try SharedPendingItemsStore.load(key: key)
            passkeys = SharedCredentialMatcher.mergingPendingPasskeys(vault: passkeys, pending: pending)
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
        // Extract domains from service identifiers; the matcher treats an
        // empty domain list as "no filter" (same as the previous early returns)
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

        return SharedCredentialMatcher.credentials(credentials, matchingDomains: searchDomains)
    }

    /// Search credentials by query string
    func searchCredentials(query: String) -> [SharedPassPasswordItem] {
        SharedCredentialMatcher.credentials(credentials, matchingQuery: query)
    }

    // MARK: - Passkey Methods

    /// Find a passkey by its credential ID
    func findPasskey(credentialId: Data) -> SharedPassPasskeyItem? {
        SharedCredentialMatcher.passkey(in: passkeys, credentialId: credentialId)
    }

    /// Filter passkeys by relying party ID and the request's allowed credential list
    func filteredPasskeys(for rpId: String?, allowedCredentialIds: [Data] = []) -> [SharedPassPasskeyItem] {
        SharedCredentialMatcher.passkeys(
            passkeys,
            forRpId: rpId,
            allowedCredentialIds: Set(allowedCredentialIds.map { $0.base64URLEncodedString })
        )
    }

    /// Search passkeys by query string
    func searchPasskeys(query: String) -> [SharedPassPasskeyItem] {
        SharedCredentialMatcher.passkeys(passkeys, matchingQuery: query)
    }
}
