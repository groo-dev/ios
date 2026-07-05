//
//  SharedPadCryptoTests.swift
//  GrooTests
//
//  The app↔extension crypto contract: payloads encrypted by the app's
//  CryptoService must decrypt through SharedPadCrypto (the Widget/Keyboard
//  code path), and tampering/wrong keys must fail loudly.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPadCryptoTests {
    static func payload(from encrypted: EncryptedPayload) -> SharedPadCrypto.EncryptedPayload {
        SharedPadCrypto.EncryptedPayload(
            ciphertext: encrypted.ciphertext,
            iv: encrypted.iv,
            version: encrypted.version
        )
    }

    @Test func decryptsPayloadsProducedByCryptoService() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Pad item — سلام 👋 with unicode"

        let encrypted = try CryptoService().encrypt(plaintext, using: key)
        let decrypted = try SharedPadCrypto.decrypt(Self.payload(from: encrypted), using: key)

        #expect(decrypted == plaintext)
    }

    @Test func emptyPlaintextRoundtrips() throws {
        let key = SymmetricKey(size: .bits256)
        let encrypted = try CryptoService().encrypt("", using: key)
        #expect(try SharedPadCrypto.decrypt(Self.payload(from: encrypted), using: key) == "")
    }

    @Test func wrongKeyFailsLoudly() throws {
        let encrypted = try CryptoService().encrypt("secret", using: SymmetricKey(size: .bits256))

        #expect(throws: (any Error).self) {
            _ = try SharedPadCrypto.decrypt(Self.payload(from: encrypted), using: SymmetricKey(size: .bits256))
        }
    }

    @Test func tamperedCiphertextFailsLoudly() throws {
        let key = SymmetricKey(size: .bits256)
        let encrypted = try CryptoService().encrypt("secret", using: key)

        var bytes = try #require(Data(base64Encoded: encrypted.ciphertext))
        bytes[0] ^= 0xFF
        let tampered = SharedPadCrypto.EncryptedPayload(
            ciphertext: bytes.base64EncodedString(), iv: encrypted.iv, version: encrypted.version
        )

        #expect(throws: (any Error).self) {
            _ = try SharedPadCrypto.decrypt(tampered, using: key)
        }
    }

    @Test func malformedBase64ThrowsMalformedPayload() {
        let bad = SharedPadCrypto.EncryptedPayload(ciphertext: "%%%not-base64%%%", iv: "also bad", version: 1)

        #expect {
            _ = try SharedPadCrypto.decrypt(bad, using: SymmetricKey(size: .bits256))
        } throws: { error in
            guard case SharedPadCrypto.DecryptError.malformedPayload = error else { return false }
            return true
        }
    }

    @Test func truncatedCiphertextFailsLoudly() throws {
        // Shorter than one GCM tag — must throw, never return garbage
        let key = SymmetricKey(size: .bits256)
        let iv = try CryptoService().encrypt("x", using: key).iv
        let truncated = SharedPadCrypto.EncryptedPayload(
            ciphertext: Data([0x01, 0x02]).base64EncodedString(), iv: iv, version: 1
        )

        #expect(throws: (any Error).self) {
            _ = try SharedPadCrypto.decrypt(truncated, using: key)
        }
    }
}
