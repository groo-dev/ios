//
//  PassModelsTests.swift
//  GrooTests
//
//  Codable contract for every vault item type. Guards the multi-file switch
//  statements that must stay in sync when a new item type is added.
//

import Foundation
import Testing
@testable import Groo

struct PassModelsTests {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    // MARK: Roundtrips — every type

    @Test(arguments: VaultItemFixtures.allItemJSONs)
    func itemRoundtripsLosslessly(_ json: String) throws {
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        if case .corrupted = item { Issue.record("fixture decoded as corrupted: \(json)") }
        let reencoded = try encoder.encode(item)
        let redecoded = try decoder.decode(PassVaultItem.self, from: reencoded)
        #expect(redecoded == item)
    }

    @Test func everyItemTypeHasAFixture() {
        // If a new case is added to PassVaultItemType, this fails until a fixture exists.
        #expect(VaultItemFixtures.allItemJSONs.count == PassVaultItemType.allCases.count)
    }

    @Test func decodedTypesMatchExpectedCases() throws {
        let items = try VaultItemFixtures.allItemJSONs.map {
            try decoder.decode(PassVaultItem.self, from: Data($0.utf8))
        }
        #expect(items.map(\.type) == [.password, .passkey, .note, .card, .bankAccount, .file, .cryptoWallet])
    }

    // MARK: Type inference when "type" field is missing

    @Test func infersPasswordFromFields() throws {
        let json = """
        {"id":"x","name":"n","username":"u","password":"p","urls":[],"createdAt":1,"updatedAt":1}
        """
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .password = item else { Issue.record("expected .password, got \(item)"); return }
    }

    @Test func infersPasskeyFromRpIdAndCredentialId() throws {
        let json = """
        {"id":"x","name":"n","rpId":"r.com","rpName":"R","credentialId":"Y3JlZA","publicKey":"cA==","privateKey":"cA==","userHandle":"dQ","userName":"u","signCount":0,"createdAt":1,"updatedAt":1}
        """
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .passkey = item else { Issue.record("expected .passkey, got \(item)"); return }
    }

    // MARK: Corruption safety — bad items must never destroy data

    @Test func malformedItemBecomesCorruptedAndPreservesOriginalJSON() throws {
        // "card" type but missing all required card fields → decode fails → .corrupted
        let json = """
        {"id":"bad-1","type":"card","name":"Broken","customField":42}
        """
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .corrupted(let corrupted) = item else {
            Issue.record("expected .corrupted, got \(item)"); return
        }
        #expect(corrupted.id == "bad-1")

        // Re-encoding must emit the ORIGINAL json verbatim (via PassRawJSON)
        let reencoded = try encoder.encode(item)
        let original = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! NSDictionary
        let roundtripped = try JSONSerialization.jsonObject(with: reencoded) as! NSDictionary
        #expect(roundtripped == original)
    }

    // MARK: Vault roundtrip

    @Test func fullVaultRoundtrips() throws {
        let itemsJSON = VaultItemFixtures.allItemJSONs.joined(separator: ",")
        let vaultJSON = """
        {"version":1,"items":[\(itemsJSON)],"folders":[{"id":"f-1","name":"Work"}],"lastModified":1700000000000}
        """
        let vault = try decoder.decode(PassVault.self, from: Data(vaultJSON.utf8))
        #expect(vault.items.count == 7)
        #expect(vault.folders.map(\.name) == ["Work"])
        let redecoded = try decoder.decode(PassVault.self, from: try encoder.encode(vault))
        #expect(redecoded == vault)
    }

    // MARK: Optional-field tolerance

    @Test func minimalPasswordItemDecodes() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":[],"createdAt":1,"updatedAt":1}
        """
        let item = try decoder.decode(PassPasswordItem.self, from: Data(json.utf8))
        #expect(item.notes == nil)
        #expect(item.totp == nil)
        #expect(item.deletedAt == nil)
    }

    // MARK: Unicode / size sweep (Phase 6)

    @Test(arguments: VaultItemFixtures.unicodeItemJSONs)
    func unicodeItemRoundtripsLosslessly(_ json: String) throws {
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        if case .corrupted = item { Issue.record("unicode fixture decoded as corrupted: \(json)") }
        let redecoded = try decoder.decode(PassVaultItem.self, from: try encoder.encode(item))
        #expect(redecoded == item)
    }

    @Test func unicodeFieldsSurviveWithExactScalars() throws {
        // Fixture parity: the unicode twins must track the type list
        #expect(VaultItemFixtures.unicodeItemJSONs.count == PassVaultItemType.allCases.count)

        let item = try decoder.decode(PassVaultItem.self, from: Data(VaultItemFixtures.unicodePasswordItemJSON.utf8))
        guard case .password(let pwd) = item else { Issue.record("expected .password, got \(item)"); return }
        #expect(pwd.name == "🔐 パスワード مثال")
        #expect(pwd.password == "påsswörd🧨👨‍👩‍👧‍👦")   // ZWJ family survives as one grapheme run
        #expect(pwd.username == "ユーザー@例え.jp")
        #expect(pwd.urls == ["https://例え.jp/ログイン"])
        #expect(pwd.folderId == "📁-1")
    }

    /// Max-size sweep: a pathological but user-reachable note (a pasted
    /// document). ~100KB of multi-byte content must roundtrip untruncated.
    @Test func largeMultibyteNoteContentRoundtrips() throws {
        let bigContent = String(repeating: "секрет🗒️", count: 12_000)   // 7 Characters × 12k
        let json = #"{"id":"n-big","type":"note","name":"big","content":"\#(bigContent)","createdAt":1,"updatedAt":1}"#
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .note(let note) = item else { Issue.record("expected .note, got \(item)"); return }
        #expect(note.content == bigContent)
        let redecoded = try decoder.decode(PassVaultItem.self, from: try encoder.encode(item))
        #expect(redecoded == item)
    }
}
