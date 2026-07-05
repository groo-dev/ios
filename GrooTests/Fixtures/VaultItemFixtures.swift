//
//  VaultItemFixtures.swift
//  GrooTests
//
//  Canonical JSON for every vault item type. Keys must match the CodingKeys
//  in PassModels.swift — these fixtures are the schema contract.
//

import Foundation
@testable import Groo

enum VaultItemFixtures {
    static let passwordItemJSON = """
    {"id":"pw-1","type":"password","name":"Example","username":"user@example.com","password":"hunter2!","urls":["https://www.example.com/login"],"notes":"note","totp":{"secret":"JBSWY3DPEHPK3PXP","algorithm":"SHA1","digits":6,"period":30},"folderId":"f-1","favorite":true,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let passkeyItemJSON = """
    {"id":"pk-1","type":"passkey","name":"Example Passkey","rpId":"example.com","rpName":"Example","credentialId":"Y3JlZC1pZA","publicKey":"cHVi","privateKey":"cHJpdg==","userHandle":"dXNlcg","userName":"user@example.com","signCount":0,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let noteItemJSON = """
    {"id":"n-1","type":"note","name":"Secure Note","content":"top secret 📝","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let cardItemJSON = """
    {"id":"c-1","type":"card","name":"Visa","cardholderName":"J DOE","number":"4111111111111111","expMonth":"12","expYear":"2030","cvv":"123","brand":"visa","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let bankAccountItemJSON = """
    {"id":"b-1","type":"bank_account","name":"Checking","bankName":"Big Bank","accountType":"checking","accountNumber":"12345678","routingNumber":"021000021","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let fileItemJSON = """
    {"id":"fl-1","type":"file","name":"Tax Doc","fileName":"2025.pdf","fileSize":1024,"mimeType":"application/pdf","r2Key":"files/abc","encryptionIv":"aXY=","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let cryptoWalletItemJSON = """
    {"id":"w-1","type":"crypto_wallet","name":"Main Wallet","address":"0xabc","seedPhrase":"legal winner thank year wave sausage worth useful legal winner thank yellow","derivationPath":"m/44'/60'/0'/0/0","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static var allItemJSONs: [String] {
        [passwordItemJSON, passkeyItemJSON, noteItemJSON, cardItemJSON,
         bankAccountItemJSON, fileItemJSON, cryptoWalletItemJSON]
    }

    // MARK: - Unicode/emoji twins (Phase 6 edge sweep)

    /// Every user-controlled string field carries multi-byte content — CJK,
    /// RTL Arabic, combining marks (the ́ below is a JSON escape for a
    /// combining acute), and multi-scalar ZWJ emoji. Structural fields
    /// (base64 keys, card numbers, hex addresses, mime types) stay valid:
    /// production never receives emoji there. Keep 1:1 with allItemJSONs.
    static let unicodePasswordItemJSON = """
    {"id":"pw-u","type":"password","name":"🔐 パスワード مثال","username":"ユーザー@例え.jp","password":"påsswörd🧨👨‍👩‍👧‍👦","urls":["https://例え.jp/ログイン"],"notes":"ملاحظة 📝 caf\\u00e9 vs cafe\\u0301","totp":{"secret":"JBSWY3DPEHPK3PXP","algorithm":"SHA1","digits":6,"period":30},"folderId":"📁-1","favorite":true,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodePasskeyItemJSON = """
    {"id":"pk-u","type":"passkey","name":"🗝️ 通行キー","rpId":"example.com","rpName":"مثال — Beispiel","credentialId":"Y3JlZC1pZA","publicKey":"cHVi","privateKey":"cHJpdg==","userHandle":"dXNlcg","userName":"ユーザー🙂","signCount":0,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeNoteItemJSON = """
    {"id":"n-u","type":"note","name":"📝 ملاحظات سرية","content":"秘密 🤫 mixed مع النص Ω≈ç√ — e\\u0301 combining","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeCardItemJSON = """
    {"id":"c-u","type":"card","name":"💳 бизнес карта","cardholderName":"JOSÉ GARCÍA-ÑOÑO","number":"4111111111111111","expMonth":"12","expYear":"2030","cvv":"123","brand":"visa","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeBankAccountItemJSON = """
    {"id":"b-u","type":"bank_account","name":"🏦 حساب جاري","bankName":"بنك الإمارات دبي الوطني","accountType":"checking","accountNumber":"12345678","routingNumber":"021000021","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeFileItemJSON = """
    {"id":"fl-u","type":"file","name":"📄 書類","fileName":"税務書類 2025 📎.pdf","fileSize":1024,"mimeType":"application/pdf","r2Key":"files/例え","encryptionIv":"aXY=","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeCryptoWalletItemJSON = """
    {"id":"w-u","type":"crypto_wallet","name":"🪙 المحفظة الرئيسية","address":"0xabc","seedPhrase":"legal winner thank year wave sausage worth useful legal winner thank yellow","derivationPath":"m/44'/60'/0'/0/0","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static var unicodeItemJSONs: [String] {
        [unicodePasswordItemJSON, unicodePasskeyItemJSON, unicodeNoteItemJSON, unicodeCardItemJSON,
         unicodeBankAccountItemJSON, unicodeFileItemJSON, unicodeCryptoWalletItemJSON]
    }

    /// Programmatic password item for tests needing controlled timestamps.
    static func samplePasswordItem(
        id: String = "pw-1", name: String = "Example", password: String = "hunter2!",
        totp: PassTotpConfig? = nil, updatedAt: Int = 1_700_000_000_000, deletedAt: Int? = nil
    ) -> PassPasswordItem {
        PassPasswordItem(
            id: id, type: .password, name: name, username: "user@example.com",
            password: password, urls: ["https://example.com"], notes: nil, totp: totp,
            folderId: nil, favorite: nil,
            createdAt: 1_700_000_000_000, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
