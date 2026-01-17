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

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: return "Invalid private key format"
        case .invalidBase64: return "Invalid base64 encoding"
        case .signingFailed: return "Failed to sign assertion"
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
}
