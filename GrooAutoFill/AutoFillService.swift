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
import GrooAuth
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

    /// A background refresh is in flight. The credential list stays usable
    /// throughout — this only drives a spinner.
    @Published var isRefreshing = false
    /// Set when a refresh fails. Never blocks AutoFill: the cached credentials
    /// remain fully usable, so this is informational, not fatal.
    @Published var refreshError: String?

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
            // Off the main thread: the biometric read blocks, and blocking the
            // main thread prevents the UI this prompt needs from ever appearing
            encryptionKey = try await SharedKeychain.loadEncryptionKeyOffMainThread(
                prompt: "Authenticate to access passwords"
            )
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

        // Per-item records first. A background refresh persists them, but each
        // AutoFill invocation is a fresh process — reading only the blob cache
        // rebuilt state from whatever the main app last wrote and discarded
        // everything the refresh had synced. QuickType kept suggesting the new
        // passkey (that lives in the OS store) while findPasskey could not
        // resolve it, so the sheet dismissed with credentialIdentityNotFound.
        if let cached = try? SharedRecordStore.load(key: key), !cached.records.isEmpty {
            let decoded = SharedRecordDecoder.decodeItems(cached.records, key: key)
            credentials = decoded.passwords
            passkeys = Self.withPendingPasskeys(decoded.passkeys, key: key)
            return
        }

        // No records yet (never refreshed, or still on the blob format).
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

        passkeys = Self.withPendingPasskeys(passkeys, key: key)
    }

    /// Fold in passkeys registered here but not yet merged into the vault by the
    /// main app. A queue that cannot be read must not fail the whole unlock.
    static func withPendingPasskeys(
        _ passkeys: [SharedPassPasskeyItem],
        key: SymmetricKey
    ) -> [SharedPassPasskeyItem] {
        do {
            let pending = try SharedPendingItemsStore.load(key: key)
            return SharedCredentialMatcher.mergingPendingPasskeys(vault: passkeys, pending: pending)
        } catch {
            Log.autofill.error(
                "Skipping pending passkeys: \(String(describing: error), privacy: .public)"
            )
            return passkeys
        }
    }

    // MARK: - Passkey Registration

    // MARK: - Background refresh

    /// Pull anything created or changed elsewhere since the last sync.
    ///
    /// Deliberately non-blocking: the sheet renders from cache immediately and
    /// this updates it when it lands. AutoFill must keep working with no network
    /// at all, so every failure here leaves the cached credentials untouched.
    func refreshInBackground() {
        guard let key = encryptionKey, !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil

        Task { [weak self] in
            defer { Task { @MainActor in self?.isRefreshing = false } }
            do {
                try await self?.performRefresh(using: key)
            } catch {
                await MainActor.run {
                    // Surfaced, never thrown: a failed refresh must not take
                    // away credentials the user already has.
                    self?.refreshError = Self.describeRefreshFailure(error)
                }
                Log.autofill.error(
                    "Background refresh failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    static func describeRefreshFailure(_ error: any Error) -> String {
        switch error {
        case APIError.unauthorized:
            return "Sign in to the Groo app to refresh"
        case APIError.networkError:
            return "Couldn't reach the server — showing saved items"
        default:
            return "Couldn't refresh — showing saved items"
        }
    }

    private func performRefresh(using key: SymmetricKey) async throws {
        let session = GrooAuthFactory.makeTokenOnlySession()
        let api = PassAPIClient(
            tokenProvider: { try await session.accessToken() },
            forceRefresh: { throw APIError.unauthorized }
        )

        // Records only. At format 1 the blob is authoritative and owned by the
        // app, so there is nothing safe for the extension to refresh.
        let keyInfo: SharedFormatProbe = try await api.get(PassAPIClient.Endpoint.keyInfo)
        guard (keyInfo.formatVersion ?? 1) == 2 else { return }

        // A cache that exists but cannot be read must not silently reset the
        // cursor — that would refetch every record on every sheet.
        var cached = try SharedRecordStore.load(key: key) ?? .empty

        while true {
            let page: SharedRecordsResponse = try await api.get(
                PassAPIClient.Endpoint.recordsSince(cached.cursor)
            )
            cached = SharedRecordStore.apply(cached, page: page)
            if !page.hasMore { break }
        }

        try SharedRecordStore.save(cached, key: key)

        let decoded = SharedRecordDecoder.decodeItems(cached.records, key: key)
        let mergedPasskeys = Self.withPendingPasskeys(decoded.passkeys, key: key)

        await MainActor.run {
            self.credentials = decoded.passwords
            self.passkeys = mergedPasskeys
        }

        // Refreshing the in-memory list only updates OUR sheet. The keyboard's
        // QuickType strip is driven by ASCredentialIdentityStore, which iOS
        // keeps separately — so without this a newly synced item shows in the
        // sheet but is never suggested until the main app runs.
        await updateQuickTypeIdentities(passwords: decoded.passwords, passkeys: mergedPasskeys)
    }

    /// Republish QuickType suggestions from a completed refresh.
    ///
    /// Replaces rather than adds, so items deleted elsewhere stop being
    /// suggested. Safe because a successful refresh holds the complete record
    /// set, not a partial page.
    private func updateQuickTypeIdentities(
        passwords: [SharedPassPasswordItem],
        passkeys: [SharedPassPasskeyItem]
    ) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { return }

        var identities: [any ASCredentialIdentity] = passwords.flatMap {
            item -> [ASPasswordCredentialIdentity] in
            item.urls.compactMap { urlString in
                // Saved URLs may be bare domains; URL(string:) yields no host
                // for those, so force a scheme before parsing.
                let normalized = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
                guard let host = URL(string: normalized)?.host else { return nil }
                return ASPasswordCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                    user: item.username,
                    recordIdentifier: item.id
                )
            }
        }

        if #available(iOS 17.0, *) {
            identities.append(contentsOf: passkeys.compactMap { passkey in
                guard
                    let credentialID = Data(base64URLEncoded: passkey.credentialId),
                    let userHandle = Data(base64URLEncoded: passkey.userHandle)
                else { return nil }
                return ASPasskeyCredentialIdentity(
                    relyingPartyIdentifier: passkey.rpId,
                    userName: passkey.userName,
                    credentialID: credentialID,
                    userHandle: userHandle,
                    recordIdentifier: passkey.id
                )
            })
        }

        do {
            try await store.replaceCredentialIdentities(identities)
        } catch {
            // QuickType drifts from the vault when this fails, but the sheet
            // itself is unaffected — so log rather than surface.
            Log.autofill.error(
                "Failed to update QuickType identities: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Persist a newly registered passkey to the pending queue for the main app to sync
    func savePendingPasskey(_ item: SharedPassPasskeyItem) throws {
        guard let key = encryptionKey else {
            throw AutoFillError.vaultLocked
        }
        try SharedPendingItemsStore.append(item, key: key)
        passkeys.append(item)
    }

    /// Push a freshly registered passkey to the server, bounded by a deadline.
    ///
    /// Never throws: the registration ceremony must complete regardless of what
    /// happens here. A failure leaves the passkey in the pending queue, which
    /// the app drains on its next sync or foreground.
    func publishPasskey(_ item: SharedPassPasskeyItem) async {
        guard let key = encryptionKey else {
            Log.autofill.error("Cannot push passkey: vault is locked")
            return
        }

        let session = GrooAuthFactory.makeTokenOnlySession()
        let api = PassAPIClient(
            tokenProvider: { try await session.accessToken() },
            // No force-refresh: one refresh attempt only. Combined with the
            // deadline below this makes a late refresh replay — which would
            // revoke the token family and sign the user out everywhere —
            // structurally impossible.
            forceRefresh: { throw APIError.unauthorized }
        )

        let publisher = PasskeyPublisher(
            pusher: APIPasskeyPusher(api: api),
            vaultKey: key
        )

        let push = Task { await publisher.publish(item) }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(SharedConfig.passkeyPushDeadlineSeconds))
            push.cancel()
        }
        let outcome = await push.value
        deadline.cancel()

        if case .queued(let reason) = outcome {
            Log.autofill.error("Passkey left queued: \(reason, privacy: .public)")
        }
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
