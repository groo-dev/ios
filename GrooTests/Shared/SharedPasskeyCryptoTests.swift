//
//  SharedPasskeyCryptoTests.swift
//  GrooTests
//
//  WebAuthn passkey crypto: sign/verify roundtrips, authenticator data layout,
//  and the sign-count-stays-zero rule.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPasskeyCryptoTests {

    // MARK: Assertion signing

    @Test func signAssertionVerifiesWithPublicKey() throws {
        let privateKey = P256.Signing.PrivateKey()
        let authData = SharedPasskeyCrypto.buildAuthenticatorData(rpId: "example.com", signCount: 0)
        let clientDataHash = Data(SHA256.hash(data: Data("client-data".utf8)))

        let derSignature = try SharedPasskeyCrypto.signAssertion(
            privateKeyBase64: privateKey.derRepresentation.base64EncodedString(),
            authenticatorData: authData,
            clientDataHash: clientDataHash
        )

        let signature = try P256.Signing.ECDSASignature(derRepresentation: derSignature)
        var signedData = authData
        signedData.append(clientDataHash)
        #expect(privateKey.publicKey.isValidSignature(signature, for: signedData))
    }

    @Test func signAssertionRejectsInvalidBase64() {
        #expect(throws: PasskeyCryptoError.invalidBase64) {
            try SharedPasskeyCrypto.signAssertion(
                privateKeyBase64: "%%% not base64 %%%",
                authenticatorData: Data(), clientDataHash: Data())
        }
    }

    @Test func signAssertionRejectsGarbageKey() {
        #expect(throws: PasskeyCryptoError.invalidPrivateKey) {
            try SharedPasskeyCrypto.signAssertion(
                privateKeyBase64: Data("valid base64, invalid DER key".utf8).base64EncodedString(),
                authenticatorData: Data(), clientDataHash: Data())
        }
    }

    // MARK: Authenticator data layout: rpIdHash(32) + flags(1) + signCount(4)

    @Test func authenticatorDataLayout() {
        let authData = SharedPasskeyCrypto.buildAuthenticatorData(rpId: "groo.dev", signCount: 7)
        #expect(authData.count == 37)
        #expect(authData.prefix(32) == Data(SHA256.hash(data: Data("groo.dev".utf8))))
        #expect(authData[32] == 0x05)  // UP | UV
        #expect(Array(authData.suffix(4)) == [0x00, 0x00, 0x00, 0x07])  // big-endian
    }

    @Test func authenticatorDataFlagVariants() {
        #expect(SharedPasskeyCrypto.buildAuthenticatorData(rpId: "x", signCount: 0, userPresent: true,  userVerified: false)[32] == 0x01)
        #expect(SharedPasskeyCrypto.buildAuthenticatorData(rpId: "x", signCount: 0, userPresent: false, userVerified: true)[32] == 0x04)
        #expect(SharedPasskeyCrypto.buildAuthenticatorData(rpId: "x", signCount: 0, userPresent: false, userVerified: false)[32] == 0x00)
    }

    // MARK: Registration

    @Test func registrationProducesUsableKeyPair() throws {
        let reg = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")

        #expect(reg.credentialId.count == 16)

        // Private key must import and match the exported public key
        let privateKey = try P256.Signing.PrivateKey(
            derRepresentation: Data(base64Encoded: reg.privateKeyBase64)!)
        let publicKey = try P256.Signing.PublicKey(
            derRepresentation: Data(base64Encoded: reg.publicKeyBase64)!)
        #expect(privateKey.publicKey.derRepresentation == publicKey.derRepresentation)
    }

    @Test func registrationCredentialIdsAreUnique() throws {
        let a = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        let b = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        #expect(a.credentialId != b.credentialId)
    }

    /// The documented AutoFill rule: registrations always embed sign count 0.
    /// authData layout inside the attestation: rpIdHash(32) + flags(0x45) + signCount(4 zero bytes) + ...
    @Test func registrationSignCountIsZero() throws {
        let reg = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        var expectedPrefix = Data(SHA256.hash(data: Data("groo.dev".utf8)))
        expectedPrefix.append(0x45)                                // UP | UV | AT
        expectedPrefix.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // sign count MUST be 0
        #expect(reg.attestationObject.range(of: expectedPrefix) != nil)
    }

    @Test func attestationObjectIsNoneFormatCbor() throws {
        let reg = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        #expect(reg.attestationObject.first == 0xa3)                       // CBOR map(3)
        #expect(reg.attestationObject.range(of: Data("none".utf8)) != nil) // fmt: "none"
        #expect(reg.attestationObject.range(of: reg.credentialId) != nil)  // embeds credential id
    }
}
