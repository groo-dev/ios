//
//  SharedCredentialMatcherTests.swift
//  GrooTests
//
//  Domain↔credential matching, query search, passkey allow-list filtering,
//  and pending-queue merge — the pure logic behind AutoFill suggestions.
//

import Foundation
import Testing
@testable import Groo

struct SharedCredentialMatcherTests {
    /// SharedPassPasswordItem has no memberwise init (custom Decodable
    /// initializer suppresses it) — build fixtures through the decoder,
    /// which also keeps them honest against the wire format.
    static func credential(
        id: String = "c-1",
        name: String = "Example",
        username: String = "user@example.com",
        urls: [String]
    ) throws -> SharedPassPasswordItem {
        let urlsJSON = urls.map { #""\#($0)""# }.joined(separator: ",")
        let json = #"{"id":"\#(id)","type":"password","name":"\#(name)","username":"\#(username)","password":"pw","urls":[\#(urlsJSON)]}"#
        return try JSONDecoder().decode(SharedPassPasswordItem.self, from: Data(json.utf8))
    }

    static func passkey(
        id: String = "pk-1",
        name: String = "Example",
        rpId: String = "example.com",
        credentialId: String = "Y3JlZC1pZA"
    ) -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: id, name: name, rpId: rpId, rpName: rpId,
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: "dXNlcg", userName: "user@example.com"
        )
    }

    // MARK: - Domain matching

    @Test func domainsMatchExactAndSubdomainsBothDirections() {
        #expect(SharedCredentialMatcher.domainsMatch("google.com", "google.com"))
        #expect(SharedCredentialMatcher.domainsMatch("accounts.google.com", "google.com"))
        #expect(SharedCredentialMatcher.domainsMatch("google.com", "accounts.google.com"))
        #expect(!SharedCredentialMatcher.domainsMatch("google.com", "github.com"))
    }

    @Test func lookalikeDomainsNeverMatch() {
        // The dot-anchored suffix rule: "app.com" must not unlock "myapp.com"
        #expect(!SharedCredentialMatcher.domainsMatch("myapp.com", "app.com"))
        #expect(!SharedCredentialMatcher.domainsMatch("app.com", "myapp.com"))
        #expect(!SharedCredentialMatcher.domainsMatch("oo.dev", "groo.dev"))
    }

    @Test func emptySearchDomainsReturnsAllCredentials() throws {
        let credentials = [
            try Self.credential(id: "c-1", urls: ["https://a.com"]),
            try Self.credential(id: "c-2", urls: ["https://b.io"]),
        ]
        let result = SharedCredentialMatcher.credentials(credentials, matchingDomains: [])
        #expect(result.map(\.id) == ["c-1", "c-2"])
    }

    @Test func credentialMatchesViaAnyOfItsSavedUrls() throws {
        let credentials = [
            try Self.credential(id: "multi", urls: ["https://mail.google.com", "github.com"]),
            try Self.credential(id: "other", urls: ["https://example.com"]),
        ]
        let result = SharedCredentialMatcher.credentials(credentials, matchingDomains: ["github.com"])
        #expect(result.map(\.id) == ["multi"])
    }

    @Test func subdomainSearchMatchesSavedRootDomain() throws {
        let credentials = [try Self.credential(id: "root", urls: ["google.com"])]
        let fromSubdomain = SharedCredentialMatcher.credentials(credentials, matchingDomains: ["accounts.google.com"])
        #expect(fromSubdomain.map(\.id) == ["root"])

        let saved = [try Self.credential(id: "sub", urls: ["https://accounts.google.com"])]
        let fromRoot = SharedCredentialMatcher.credentials(saved, matchingDomains: ["google.com"])
        #expect(fromRoot.map(\.id) == ["sub"])
    }

    @Test func credentialWithoutParseableUrlsNeverMatches() throws {
        let credentials = [try Self.credential(id: "no-urls", urls: [])]
        let result = SharedCredentialMatcher.credentials(credentials, matchingDomains: ["example.com"])
        #expect(result.isEmpty)
    }

    // MARK: - Query search

    @Test func querySearchIsCaseInsensitiveAcrossNameUsernameAndUrls() throws {
        let credentials = [
            try Self.credential(id: "by-name", name: "GitHub", urls: ["https://a.com"]),
            try Self.credential(id: "by-user", username: "GITHUB-bot@x.com", urls: ["https://b.com"]),
            try Self.credential(id: "by-url", urls: ["https://github.com/login"]),
            try Self.credential(id: "no-hit", name: "Example", urls: ["https://example.com"]),
        ]
        let result = SharedCredentialMatcher.credentials(credentials, matchingQuery: "github")
        #expect(result.map(\.id) == ["by-name", "by-user", "by-url"])
        #expect(SharedCredentialMatcher.credentials(credentials, matchingQuery: "").count == 4)
    }

    // MARK: - Passkeys

    @Test func passkeysFilterByRpIdAndAllowList() {
        let passkeys = [
            Self.passkey(id: "pk-1", rpId: "example.com", credentialId: "aWQtMQ"),
            Self.passkey(id: "pk-2", rpId: "example.com", credentialId: "aWQtMg"),
            Self.passkey(id: "pk-3", rpId: "other.com", credentialId: "aWQtMw"),
        ]

        #expect(SharedCredentialMatcher.passkeys(passkeys, forRpId: nil, allowedCredentialIds: []).isEmpty)
        #expect(SharedCredentialMatcher.passkeys(passkeys, forRpId: "example.com", allowedCredentialIds: []).map(\.id) == ["pk-1", "pk-2"])
        #expect(SharedCredentialMatcher.passkeys(passkeys, forRpId: "example.com", allowedCredentialIds: ["aWQtMg"]).map(\.id) == ["pk-2"])
    }

    @Test func findPasskeyComparesRawBytesAgainstStoredBase64URL() {
        // "cred-id" bytes → base64url "Y3JlZC1pZA" (no padding)
        let passkeys = [Self.passkey(id: "pk-1", credentialId: "Y3JlZC1pZA")]

        let found = SharedCredentialMatcher.passkey(in: passkeys, credentialId: Data("cred-id".utf8))
        #expect(found?.id == "pk-1")
        #expect(SharedCredentialMatcher.passkey(in: passkeys, credentialId: Data("other".utf8)) == nil)
    }

    @Test func mergingPendingPasskeysDedupesByCredentialIdVaultWins() {
        let vault = [Self.passkey(id: "vault-copy", credentialId: "aWQtMQ")]
        let pending = [
            Self.passkey(id: "stale-pending", credentialId: "aWQtMQ"),   // already merged into the vault
            Self.passkey(id: "fresh-pending", credentialId: "aWQtMg"),
        ]

        let merged = SharedCredentialMatcher.mergingPendingPasskeys(vault: vault, pending: pending)
        #expect(merged.map(\.id) == ["vault-copy", "fresh-pending"])
    }
}
