//
//  CredentialIdentityServiceTests.swift
//  GrooTests
//
//  QuickType identity payload building: URL normalization, per-URL fan-out,
//  deleted/malformed record exclusion, base64url decoding for passkeys.
//  (The ASCredentialIdentityStore round-trip itself is entitlement-gated and
//  stays manual-smoke territory.)
//

import AuthenticationServices
import Foundation
import Testing
@testable import Groo

struct CredentialIdentityServiceTests {
    static func passwordItem(
        id: String,
        urls: [String],
        username: String = "user@example.com",
        deletedAt: Int? = nil
    ) -> PassPasswordItem {
        PassPasswordItem(
            id: id, type: .password, name: "Item", username: username, password: "pw",
            urls: urls, notes: nil, totp: nil, folderId: nil, favorite: nil,
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000, deletedAt: deletedAt
        )
    }

    static func passkeyItem(
        id: String,
        rpId: String = "example.com",
        credentialId: String = "Y3JlZC1pZA",
        userHandle: String = "dXNlcg",
        deletedAt: Int? = nil
    ) -> PassPasskeyItem {
        var item = PassPasskeyItem(
            id: id, name: rpId, rpId: rpId, rpName: rpId,
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: userHandle, userName: "user@example.com", signCount: 0,
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000
        )
        item.deletedAt = deletedAt
        return item
    }

    // MARK: - Password identities

    @Test func schemelessUrlsAreNormalizedAndHostsLowercased() throws {
        // Saved URLs are often bare domains — the https:// prefix rule is what
        // makes them appear in QuickType at all
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [.password(Self.passwordItem(id: "p-1", urls: ["MyApp.Example.COM"]))]

        let identities = service.buildPasswordIdentities(from: items)

        let identity = try #require(identities.first)
        #expect(identities.count == 1)
        #expect(identity.serviceIdentifier.identifier == "myapp.example.com")
        #expect(identity.serviceIdentifier.type == .domain)
        #expect(identity.user == "user@example.com")
        #expect(identity.recordIdentifier == "p-1")
    }

    @Test func oneIdentityPerSavedUrl() {
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [.password(Self.passwordItem(id: "p-1", urls: ["https://a.com/login", "b.io"]))]

        let identities = service.buildPasswordIdentities(from: items)

        #expect(identities.map(\.serviceIdentifier.identifier) == ["a.com", "b.io"])
        #expect(identities.allSatisfy { $0.recordIdentifier == "p-1" })
    }

    @Test func deletedAndNonPasswordItemsProduceNoPasswordIdentities() {
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [
            .password(Self.passwordItem(id: "trashed", urls: ["https://a.com"], deletedAt: 1_700_000_000_000)),
            .password(Self.passwordItem(id: "no-urls", urls: [])),
            .passkey(Self.passkeyItem(id: "pk-1")),
        ]

        #expect(service.buildPasswordIdentities(from: items).isEmpty)
    }

    // MARK: - Passkey identities

    @Test func passkeyIdentityDecodesBase64URLFields() throws {
        let service = CredentialIdentityService()
        // "Y3JlZC1pZA" → "cred-id", "dXNlcg" → "user"
        let items: [PassVaultItem] = [.passkey(Self.passkeyItem(id: "pk-1"))]

        let identities = service.buildPasskeyIdentities(from: items)

        let identity = try #require(identities.first)
        #expect(identities.count == 1)
        #expect(identity.relyingPartyIdentifier == "example.com")
        #expect(identity.credentialID == Data("cred-id".utf8))
        #expect(identity.userHandle == Data("user".utf8))
        #expect(identity.userName == "user@example.com")
        #expect(identity.recordIdentifier == "pk-1")
    }

    @Test func malformedAndDeletedPasskeysAreSkippedNotCrashed() {
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [
            .passkey(Self.passkeyItem(id: "bad-b64", credentialId: "!!!not-base64url!!!")),
            .passkey(Self.passkeyItem(id: "trashed", deletedAt: 1_700_000_000_000)),
            .password(Self.passwordItem(id: "p-1", urls: ["https://a.com"])),
        ]

        #expect(service.buildPasskeyIdentities(from: items).isEmpty)
    }
}
