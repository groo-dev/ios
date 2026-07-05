//
//  CryptoServiceTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct CryptoServiceTests {
    let crypto = CryptoService()
    /// Fast test key — NEVER use production 600k iterations in tests.
    var key: SymmetricKey {
        get throws { try crypto.deriveKey(password: "correct horse", salt: Data("fixed-salt".utf8), iterations: 1_000) }
    }

    // MARK: Key derivation

    @Test func deriveKeyIsDeterministic() throws {
        let salt = Data("salt-a".utf8)
        let k1 = try crypto.deriveKey(password: "pw", salt: salt, iterations: 1_000)
        let k2 = try crypto.deriveKey(password: "pw", salt: salt, iterations: 1_000)
        #expect(k1 == k2)
    }

    @Test func deriveKeyDiffersBySaltPasswordAndIterations() throws {
        let base = try crypto.deriveKey(password: "pw", salt: Data("salt-a".utf8), iterations: 1_000)
        #expect(try crypto.deriveKey(password: "pw", salt: Data("salt-b".utf8), iterations: 1_000) != base)
        #expect(try crypto.deriveKey(password: "pw2", salt: Data("salt-a".utf8), iterations: 1_000) != base)
        #expect(try crypto.deriveKey(password: "pw", salt: Data("salt-a".utf8), iterations: 1_001) != base)
    }

    /// RFC 7914 §11 PBKDF2-HMAC-SHA256 vectors (first 32 bytes of dkLen=64 output).
    @Test func deriveKeyMatchesRFC7914Vectors() throws {
        let v1 = try crypto.deriveKey(password: "passwd", salt: Data("salt".utf8), iterations: 1)
        #expect(v1.withUnsafeBytes { Data($0) } ==
                Data(hexString: "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc"))

        let v2 = try crypto.deriveKey(password: "Password", salt: Data("NaCl".utf8), iterations: 80_000)
        #expect(v2.withUnsafeBytes { Data($0) } ==
                Data(hexString: "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56"))
    }

    @Test func generateSaltIs32RandomBytes() {
        let s1 = crypto.generateSalt()
        let s2 = crypto.generateSalt()
        #expect(s1.count == 32)
        #expect(s1 != s2)
    }

    // MARK: Text roundtrips

    @Test(arguments: ["hello", "", "påsswörd 🔑🧨 中文", String(repeating: "x", count: 1_000_000)])
    func encryptDecryptRoundtrip(_ plaintext: String) throws {
        let payload = try crypto.encrypt(plaintext, using: try key)
        #expect(try crypto.decrypt(payload, using: try key) == plaintext)
    }

    @Test func encryptUsesFreshNonces() throws {
        let a = try crypto.encrypt("same", using: try key)
        let b = try crypto.encrypt("same", using: try key)
        #expect(a.iv != b.iv)
        #expect(a.ciphertext != b.ciphertext)
    }

    // MARK: Failure must be loud

    @Test func decryptWithWrongKeyThrows() throws {
        let payload = try crypto.encrypt("secret", using: try key)
        let wrongKey = try crypto.deriveKey(password: "wrong", salt: Data("fixed-salt".utf8), iterations: 1_000)
        #expect(throws: (any Error).self) { try crypto.decrypt(payload, using: wrongKey) }
    }

    @Test func decryptTamperedCiphertextThrows() throws {
        let payload = try crypto.encrypt("secret", using: try key)
        var raw = Data(base64Encoded: payload.ciphertext)!
        raw[0] ^= 0xFF
        let tampered = EncryptedPayload(ciphertext: raw.base64EncodedString(), iv: payload.iv, version: payload.version)
        #expect(throws: (any Error).self) { try crypto.decrypt(tampered, using: try key) }
    }

    @Test func decryptInvalidBase64Throws() throws {
        let bad = EncryptedPayload(ciphertext: "not base64!!!", iv: "also not!!!", version: 1)
        #expect(throws: CryptoError.invalidBase64) { try crypto.decrypt(bad, using: try key) }
    }

    // MARK: Binary format

    @Test func encryptDataFormatIsIvCiphertextTag() throws {
        let plaintext = Data("binary-payload".utf8)
        let combined = try crypto.encryptData(plaintext, using: try key)
        // [12-byte IV][ciphertext][16-byte tag]
        #expect(combined.count == 12 + plaintext.count + 16)
        #expect(try crypto.decryptData(combined, using: try key) == plaintext)
    }

    // MARK: verifyKey

    @Test func verifyKeyAcceptsRightKeyRejectsWrong() throws {
        let payload = try crypto.createTestPayload(using: try key)
        #expect(crypto.verifyKey(try key, with: payload))
        let wrongKey = try crypto.deriveKey(password: "nope", salt: Data("fixed-salt".utf8), iterations: 1_000)
        #expect(!crypto.verifyKey(wrongKey, with: payload))
    }

    // MARK: SharedCrypto must decrypt what CryptoService encrypts

    @Test func sharedCryptoDecryptsCryptoServiceOutput() throws {
        let payload = try crypto.encrypt("cross-module plaintext ✓", using: try key)
        let decrypted = try SharedCrypto.decryptVault(
            encryptedData: Data(base64Encoded: payload.ciphertext)!,
            iv: payload.iv,
            key: try key
        )
        #expect(decrypted == "cross-module plaintext ✓")
    }

    @Test func sharedCryptoRejectsInvalidBase64Iv() throws {
        #expect(throws: SharedCryptoError.invalidBase64) {
            try SharedCrypto.decryptVault(encryptedData: Data(), iv: "!!!", key: try key)
        }
    }
}
