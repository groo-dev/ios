//
//  CryptoServiceWrapTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct CryptoServiceWrapTests {
    private let crypto = CryptoService()

    private struct WrapVector: Decodable {
        let passphrase: String
        let salt: String
        let iterations: UInt32
        let vaultKeyRaw: String
        let wrapped: String
        let wrapIv: String
    }

    private func loadVector() throws -> WrapVector {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(
            bundle.url(forResource: "wrap-vector", withExtension: "json"),
            "wrap-vector.json is not a member of the GrooTests target"
        )
        return try JSONDecoder().decode(WrapVector.self, from: Data(contentsOf: url))
    }

    @Test func wrapUnwrapRoundTrip() throws {
        let wrapping = try crypto.deriveKey(
            password: "correct horse",
            salt: crypto.generateSalt(),
            iterations: 10_000
        )
        let vaultKey = crypto.generateContentKey()

        let payload = try crypto.wrapKey(vaultKey, using: wrapping)
        let unwrapped = try crypto.unwrapKey(payload, using: wrapping)

        #expect(
            unwrapped.withUnsafeBytes { Data($0) } == vaultKey.withUnsafeBytes { Data($0) }
        )
    }

    /// The interop guarantee: a vault key wrapped by apps/web must unwrap here.
    @Test func unwrapsCanonicalVectorFromWeb() throws {
        let vector = try loadVector()
        let salt = try #require(Data(base64Encoded: vector.salt))
        let wrapping = try crypto.deriveKey(
            password: vector.passphrase,
            salt: salt,
            iterations: vector.iterations
        )

        let vaultKey = try crypto.unwrapKey(
            EncryptedPayload(ciphertext: vector.wrapped, iv: vector.wrapIv, version: 1),
            using: wrapping
        )

        #expect(
            vaultKey.withUnsafeBytes { Data($0) }.base64EncodedString() == vector.vaultKeyRaw
        )
    }

    @Test func wrongPassphraseThrows() throws {
        let salt = crypto.generateSalt()
        let right = try crypto.deriveKey(password: "right", salt: salt, iterations: 10_000)
        let wrong = try crypto.deriveKey(password: "wrong", salt: salt, iterations: 10_000)
        let payload = try crypto.wrapKey(crypto.generateContentKey(), using: right)

        #expect(throws: CryptoError.wrongPassphrase) {
            try crypto.unwrapKey(payload, using: wrong)
        }
    }
}

/// Anchor class for locating the test bundle (Bundle(for:) needs a class).
private final class BundleToken {}
