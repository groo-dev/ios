//
//  CryptoServiceWrapTests.swift
//  GrooTests
//

import XCTest
import CryptoKit
@testable import Groo

final class CryptoServiceWrapTests: XCTestCase {
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
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "wrap-vector", withExtension: "json"),
            "wrap-vector.json is not a member of the GrooTests target"
        )
        return try JSONDecoder().decode(WrapVector.self, from: Data(contentsOf: url))
    }

    func testWrapUnwrapRoundTrip() throws {
        let wrapping = try crypto.deriveKey(
            password: "correct horse",
            salt: crypto.generateSalt(),
            iterations: 10_000
        )
        let vaultKey = crypto.generateContentKey()

        let payload = try crypto.wrapKey(vaultKey, using: wrapping)
        let unwrapped = try crypto.unwrapKey(payload, using: wrapping)

        XCTAssertEqual(
            unwrapped.withUnsafeBytes { Data($0) },
            vaultKey.withUnsafeBytes { Data($0) }
        )
    }

    /// The interop guarantee: a vault key wrapped by apps/web must unwrap here.
    func testUnwrapsCanonicalVectorFromWeb() throws {
        let vector = try loadVector()
        let salt = try XCTUnwrap(Data(base64Encoded: vector.salt))
        let wrapping = try crypto.deriveKey(
            password: vector.passphrase,
            salt: salt,
            iterations: vector.iterations
        )

        let vaultKey = try crypto.unwrapKey(
            EncryptedPayload(ciphertext: vector.wrapped, iv: vector.wrapIv, version: 1),
            using: wrapping
        )

        XCTAssertEqual(
            vaultKey.withUnsafeBytes { Data($0) }.base64EncodedString(),
            vector.vaultKeyRaw
        )
    }

    func testWrongPassphraseThrows() throws {
        let salt = crypto.generateSalt()
        let right = try crypto.deriveKey(password: "right", salt: salt, iterations: 10_000)
        let wrong = try crypto.deriveKey(password: "wrong", salt: salt, iterations: 10_000)
        let payload = try crypto.wrapKey(crypto.generateContentKey(), using: right)

        XCTAssertThrowsError(try crypto.unwrapKey(payload, using: wrong)) { error in
            XCTAssertEqual(error as? CryptoError, .wrongPassphrase)
        }
    }
}
