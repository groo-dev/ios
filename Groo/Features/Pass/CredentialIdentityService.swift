//
//  CredentialIdentityService.swift
//  Groo
//
//  Manages credential identities for AutoFill QuickType suggestions.
//  Syncs password and passkey items to ASCredentialIdentityStore.
//

import AuthenticationServices
import Foundation
import os

class CredentialIdentityService: CredentialIdentityProviding {
    private let store = ASCredentialIdentityStore.shared

    /// Update the credential identity store with current password and passkey items
    /// Call this after vault changes (add, update, delete)
    func updateCredentialIdentities(from items: [PassVaultItem]) async {
        // Check if the store supports incremental updates
        let state = await store.state()

        guard state.isEnabled else {
            // AutoFill not enabled for this app
            return
        }

        // Build password identities
        let passwordIdentities = buildPasswordIdentities(from: items)

        // Build passkey identities (iOS 17+)
        var allIdentities: [any ASCredentialIdentity] = passwordIdentities

        if #available(iOS 17.0, *) {
            let passkeyIdentities = buildPasskeyIdentities(from: items)
            allIdentities.append(contentsOf: passkeyIdentities)
        }

        // Replace all identities
        do {
            try await store.replaceCredentialIdentities(allIdentities)
        } catch {
            // QuickType drifts from the vault when this fails
            Log.pass.error("Failed to update credential identities: \(String(describing: error), privacy: .public)")
        }
    }

    /// Build password credential identities from vault items
    private func buildPasswordIdentities(from items: [PassVaultItem]) -> [ASPasswordCredentialIdentity] {
        // Extract password items
        let passwordItems = items.compactMap { item -> PassPasswordItem? in
            guard case .password(let passwordItem) = item,
                  passwordItem.deletedAt == nil else {
                return nil
            }
            return passwordItem
        }

        // Create credential identities
        return passwordItems.flatMap { item -> [ASPasswordCredentialIdentity] in
            // Create an identity for each URL
            return item.urls.compactMap { urlString -> ASPasswordCredentialIdentity? in
                // Saved URLs may be bare domains like "example.com" — URL(string:)
                // has no host for those, so ensure a scheme before parsing
                let normalized = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
                guard let url = URL(string: normalized),
                      let host = url.host else {
                    return nil
                }

                let serviceIdentifier = ASCredentialServiceIdentifier(
                    identifier: host.lowercased(),
                    type: .domain
                )

                return ASPasswordCredentialIdentity(
                    serviceIdentifier: serviceIdentifier,
                    user: item.username,
                    recordIdentifier: item.id
                )
            }
        }
    }

    /// Build passkey credential identities from vault items (iOS 17+)
    @available(iOS 17.0, *)
    private func buildPasskeyIdentities(from items: [PassVaultItem]) -> [ASPasskeyCredentialIdentity] {
        return items.compactMap { item -> ASPasskeyCredentialIdentity? in
            guard case .passkey(let passkeyItem) = item, passkeyItem.deletedAt == nil else {
                return nil
            }
            guard let credentialIdData = Data(base64URLEncoded: passkeyItem.credentialId),
                  let userHandleData = Data(base64URLEncoded: passkeyItem.userHandle) else {
                // Malformed record — this passkey will never appear in QuickType
                Log.pass.error("Passkey \(passkeyItem.id, privacy: .public) has undecodable credentialId/userHandle; skipping identity")
                return nil
            }

            return ASPasskeyCredentialIdentity(
                relyingPartyIdentifier: passkeyItem.rpId,
                userName: passkeyItem.userName,
                credentialID: credentialIdData,
                userHandle: userHandleData,
                recordIdentifier: passkeyItem.id
            )
        }
    }

    /// Clear all credential identities (call on sign out or vault lock)
    /// - Returns: false when the wipe failed — credentials stay suggested in QuickType
    @discardableResult
    func clearCredentialIdentities() async -> Bool {
        do {
            try await store.removeAllCredentialIdentities()
            return true
        } catch {
            // Security cleanup failure: deleted vault's credentials remain in QuickType
            Log.pass.fault("Failed to clear credential identities on sign-out: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
