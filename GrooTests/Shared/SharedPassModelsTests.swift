//
//  SharedPassModelsTests.swift
//  GrooTests
//
//  Extension-side mirror models: base64URL, type inference, TOTP tolerance,
//  domain matching.
//

import Foundation
import Testing
@testable import Groo

struct SharedPassModelsTests {
    let decoder = JSONDecoder()

    // MARK: Base64URL (WebAuthn credentialId / userHandle encoding)

    @Test(arguments: ["f", "fo", "foo", "foob", "fooba", "foobar", ""])
    func base64URLRoundtrips(_ raw: String) throws {
        let encoded = Data(raw.utf8).base64URLEncodedString
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        let decoded = try #require(Data(base64URLEncoded: encoded))
        #expect(String(data: decoded, encoding: .utf8) == raw)
    }

    @Test func base64URLDecodesUrlSafeChars() {
        // 0xfb 0xef 0xff encodes to "----" chars territory: base64 "++//" → base64url "--__"
        let data = Data([0xfb, 0xef, 0xff, 0xbe])
        let encoded = data.base64URLEncodedString
        #expect(Data(base64URLEncoded: encoded) == data)
    }

    // MARK: Item decoding for AutoFill

    @Test func passwordAndPasskeyDecodeOthersCollapse() throws {
        let vaultJSON = """
        {"version":1,"items":[
          \(VaultItemFixtures.passwordItemJSON),
          \(VaultItemFixtures.passkeyItemJSON),
          \(VaultItemFixtures.noteItemJSON)
        ],"folders":[],"lastModified":1}
        """
        let vault = try decoder.decode(SharedPassVault.self, from: Data(vaultJSON.utf8))
        #expect(vault.items.count == 3)
        #expect(vault.items.compactMap(\.passwordItem).count == 1)
        #expect(vault.items.compactMap(\.passkeyItem).count == 1)
    }

    /// A malformed TOTP config must not take the whole credential down.
    @Test func malformedTotpIsToleratedCredentialSurvives() throws {
        let json = """
        {"id":"pw-1","type":"password","name":"n","username":"u","password":"p","urls":[],"totp":{"secret":"s","algorithm":"NOT_AN_ALGO","digits":6,"period":30}}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.password == "p")
        #expect(item.totp == nil)
    }

    // MARK: Domain matching

    @Test func primaryDomainStripsWwwAndLowercases() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":["https://WWW.Example.COM/login"]}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.primaryDomain == "example.com")
    }

    @Test func domainsHandleBareHostsAndSchemes() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":["example.com","https://app.groo.dev/x","www.foo.io"]}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.domains == ["example.com", "app.groo.dev", "foo.io"])
    }

    @Test func primaryDomainIsNilForEmptyUrls() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":[]}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.primaryDomain == nil)
    }

    // MARK: Unicode sweep (Phase 6)

    /// AutoFill fills what the app stored: multi-byte credentials must cross
    /// the extension-side decode with exact scalar fidelity, and unicode
    /// URLs must never crash domain extraction (the exact host rendering —
    /// punycode or bail — is Foundation's business, so it is not pinned).
    @Test func unicodeCredentialSurvivesSharedDecode() throws {
        let item = try decoder.decode(SharedPassPasswordItem.self,
                                      from: Data(VaultItemFixtures.unicodePasswordItemJSON.utf8))
        #expect(item.password == "påsswörd🧨👨‍👩‍👧‍👦")
        #expect(item.username == "ユーザー@例え.jp")
        #expect(item.name == "🔐 パスワード مثال")
        _ = item.primaryDomain   // crash-freedom pin on the unicode URL
        _ = item.domains
    }
}
