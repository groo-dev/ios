//
//  SharedPasskeyCrypto.swift
//  Groo
//
//  ECDSA P-256 signing for WebAuthn passkey assertions.
//  Used by AutoFill extension to sign passkey authentication requests.
//

import CryptoKit
import Foundation

enum PasskeyCryptoError: Error, LocalizedError {
    case invalidPrivateKey
    case invalidBase64
    case signingFailed
    case keyGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: return "Invalid private key format"
        case .invalidBase64: return "Invalid base64 encoding"
        case .signingFailed: return "Failed to sign assertion"
        case .keyGenerationFailed: return "Failed to generate passkey"
        }
    }
}

@available(iOS 17.0, *)
enum SharedPasskeyCrypto {

    /// Sign a WebAuthn assertion with ECDSA P-256
    /// - Parameters:
    ///   - privateKeyBase64: PKCS8-encoded private key (base64)
    ///   - authenticatorData: The authenticator data bytes
    ///   - clientDataHash: SHA-256 hash of clientDataJSON
    /// - Returns: DER-encoded ECDSA signature
    static func signAssertion(
        privateKeyBase64: String,
        authenticatorData: Data,
        clientDataHash: Data
    ) throws -> Data {
        // Decode private key from base64
        guard let privateKeyData = Data(base64Encoded: privateKeyBase64) else {
            throw PasskeyCryptoError.invalidBase64
        }

        // Import PKCS8 key to CryptoKit P256 private key
        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(derRepresentation: privateKeyData)
        } catch {
            throw PasskeyCryptoError.invalidPrivateKey
        }

        // Build signed data: authenticatorData || clientDataHash
        var signedData = authenticatorData
        signedData.append(clientDataHash)

        // Sign with ECDSA P-256
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try privateKey.signature(for: signedData)
        } catch {
            throw PasskeyCryptoError.signingFailed
        }

        // Return DER-encoded signature (WebAuthn expects DER format)
        return signature.derRepresentation
    }

    /// Build authenticator data for an assertion
    /// - Parameters:
    ///   - rpId: Relying party identifier (domain)
    ///   - signCount: Current sign count (will be incremented by caller)
    ///   - userPresent: User presence flag (default true)
    ///   - userVerified: User verification flag (default true for biometric)
    /// - Returns: Authenticator data bytes (37 bytes for assertion without extensions)
    static func buildAuthenticatorData(
        rpId: String,
        signCount: Int,
        userPresent: Bool = true,
        userVerified: Bool = true
    ) -> Data {
        // Hash RP ID with SHA-256 (32 bytes)
        let rpIdHash = SHA256.hash(data: Data(rpId.utf8))

        // Flags byte: UP (bit 0) + UV (bit 2)
        var flags: UInt8 = 0
        if userPresent { flags |= 0x01 }   // bit 0: User Present
        if userVerified { flags |= 0x04 }  // bit 2: User Verified

        // Build authenticator data: rpIdHash (32) + flags (1) + signCount (4) = 37 bytes
        var authData = Data(rpIdHash)
        authData.append(flags)

        // Sign count as big-endian 32-bit unsigned integer
        var signCountBE = UInt32(signCount).bigEndian
        authData.append(Data(bytes: &signCountBE, count: 4))

        return authData
    }

    // MARK: - Registration

    /// Result of creating a new passkey credential
    struct Registration {
        let credentialId: Data
        let privateKeyBase64: String   // PKCS8 DER, base64
        let publicKeyBase64: String    // SPKI DER, base64
        let attestationObject: Data
    }

    /// Create a new P-256 passkey for registration (WebAuthn "none" attestation)
    static func createRegistration(rpId: String) throws -> Registration {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        // Random 16-byte credential ID
        var credentialId = Data(count: 16)
        let status = credentialId.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PasskeyCryptoError.keyGenerationFailed
        }

        // COSE_Key (EC2, ES256): {1: 2, 3: -7, -1: 1, -2: x, -3: y}
        let xy = publicKey.x963Representation.dropFirst() // strip 0x04 prefix
        let x = xy.prefix(32)
        let y = xy.suffix(32)
        var coseKey = Data([0xa5])                    // map(5)
        coseKey.append(contentsOf: [0x01, 0x02])      // 1 (kty): 2 (EC2)
        coseKey.append(contentsOf: [0x03, 0x26])      // 3 (alg): -7 (ES256)
        coseKey.append(contentsOf: [0x20, 0x01])      // -1 (crv): 1 (P-256)
        coseKey.append(contentsOf: [0x21, 0x58, 0x20]) // -2 (x): bytes(32)
        coseKey.append(x)
        coseKey.append(contentsOf: [0x22, 0x58, 0x20]) // -3 (y): bytes(32)
        coseKey.append(y)

        // Authenticator data with attested credential data:
        // rpIdHash(32) + flags(UP|UV|AT) + signCount(4) + aaguid(16) + credIdLen(2) + credId + coseKey
        var authData = Data(SHA256.hash(data: Data(rpId.utf8)))
        authData.append(0x45) // UP (0x01) + UV (0x04) + AT (0x40)
        authData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // sign count 0
        authData.append(Data(count: 16)) // zero AAGUID
        authData.append(contentsOf: [UInt8(credentialId.count >> 8), UInt8(credentialId.count & 0xff)])
        authData.append(credentialId)
        authData.append(coseKey)

        // Attestation object: {"fmt": "none", "attStmt": {}, "authData": authData}
        var attestation = Data([0xa3])                       // map(3)
        attestation.append(cborTextString("fmt"))
        attestation.append(cborTextString("none"))
        attestation.append(cborTextString("attStmt"))
        attestation.append(0xa0)                             // empty map
        attestation.append(cborTextString("authData"))
        attestation.append(cborByteStringHeader(count: authData.count))
        attestation.append(authData)

        return Registration(
            credentialId: credentialId,
            privateKeyBase64: privateKey.derRepresentation.base64EncodedString(),
            publicKeyBase64: publicKey.derRepresentation.base64EncodedString(),
            attestationObject: attestation
        )
    }

    // MARK: - Minimal CBOR Helpers

    private static func cborTextString(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        var data = cborHeader(major: 3, count: bytes.count)
        data.append(bytes)
        return data
    }

    private static func cborByteStringHeader(count: Int) -> Data {
        cborHeader(major: 2, count: count)
    }

    private static func cborHeader(major: UInt8, count: Int) -> Data {
        let majorBits = major << 5
        switch count {
        case 0..<24:
            return Data([majorBits | UInt8(count)])
        case 24..<256:
            return Data([majorBits | 24, UInt8(count)])
        default:
            return Data([majorBits | 25, UInt8(count >> 8), UInt8(count & 0xff)])
        }
    }
}
