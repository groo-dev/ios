//
//  CredentialIdentityService.swift
//  Groo
//
//  Manages credential identities for AutoFill QuickType suggestions.
//  Syncs password items to ASCredentialIdentityStore.
//

import AuthenticationServices
import Foundation

class CredentialIdentityService {
    private let store = ASCredentialIdentityStore.shared

    /// Update the credential identity store with current password items
    /// Call this after vault changes (add, update, delete)
    func updateCredentialIdentities(from items: [PassVaultItem]) async {
        // Check if the store supports incremental updates
        let state = await store.state()

        guard state.isEnabled else {
            // AutoFill not enabled for this app
            return
        }

        // Extract password items
        let passwordItems = items.compactMap { item -> PassPasswordItem? in
            guard case .password(let passwordItem) = item,
                  passwordItem.deletedAt == nil else {
                return nil
            }
            return passwordItem
        }

        // Create credential identities
        let identities = passwordItems.flatMap { item -> [ASPasswordCredentialIdentity] in
            // Create an identity for each URL
            return item.urls.compactMap { urlString -> ASPasswordCredentialIdentity? in
                guard let url = URL(string: urlString),
                      let host = url.host else {
                    return nil
                }

                let serviceIdentifier = ASCredentialServiceIdentifier(
                    identifier: host,
                    type: .domain
                )

                return ASPasswordCredentialIdentity(
                    serviceIdentifier: serviceIdentifier,
                    user: item.username,
                    recordIdentifier: item.id
                )
            }
        }

        // Replace all identities
        do {
            try await store.replaceCredentialIdentities(identities)
        } catch {
            print("Failed to update credential identities: \(error)")
        }
    }

    /// Clear all credential identities (call on sign out or vault lock)
    func clearCredentialIdentities() async {
        do {
            try await store.removeAllCredentialIdentities()
        } catch {
            print("Failed to clear credential identities: \(error)")
        }
    }
}
