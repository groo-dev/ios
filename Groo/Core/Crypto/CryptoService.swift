//
//  CryptoService.swift
//  Groo
//
//  E2E Encryption using PBKDF2 + AES-256-GCM.
//  Must match web/CLI implementation exactly.
//

import CryptoKit
import Foundation
import CommonCrypto

// MARK: - Constants

private let pbkdf2Iterations: UInt32 = 600_000
private let saltLength = 32
private let ivLength = 12
private let keyLength = 32
private let encryptionVersion = 1

// MARK: - Types

struct EncryptedPayload: Codable {
    let ciphertext: String  // base64 encoded
    let iv: String          // base64 encoded
    let version: Int
}

enum CryptoError: Error {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidPayload
    case invalidBase64
}

// MARK: - CryptoService

struct CryptoService {

    // MARK: - Salt Generation

    /// Generate a random 32-byte salt for key derivation
    func generateSalt() -> Data {
        var salt = Data(count: saltLength)
        salt.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        return salt
    }

    // MARK: - Key Derivation

    /// Derive an AES-256 key from password and salt using PBKDF2-HMAC-SHA256
    func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw CryptoError.keyDerivationFailed
        }

        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordData.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedKeyBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }

        return SymmetricKey(data: derivedKey)
    }

    // MARK: - Text Encryption

    /// Encrypt a string using AES-256-GCM
    func encrypt(_ plaintext: String, using key: SymmetricKey) throws -> EncryptedPayload {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // Combine ciphertext + tag (web crypto does this automatically)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // Extract just ciphertext + tag (without nonce, which is stored separately)
        let ciphertextWithTag = combined.dropFirst(ivLength)

        return EncryptedPayload(
            ciphertext: ciphertextWithTag.base64EncodedString(),
            iv: Data(nonce).base64EncodedString(),
            version: encryptionVersion
        )
    }

    /// Decrypt an EncryptedPayload back to string
    func decrypt(_ payload: EncryptedPayload, using key: SymmetricKey) throws -> String {
        guard let ciphertextWithTag = Data(base64Encoded: payload.ciphertext),
              let ivData = Data(base64Encoded: payload.iv) else {
            throw CryptoError.invalidBase64
        }

        let nonce = try AES.GCM.Nonce(data: ivData)

        // Reconstruct combined data (nonce + ciphertext + tag)
        var combined = Data(ivData)
        combined.append(ciphertextWithTag)

        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decrypted, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }

        return plaintext
    }

    // MARK: - Binary Encryption (for files)

    /// Encrypt binary data, returning IV prepended to ciphertext
    /// Format: [12-byte IV][ciphertext][16-byte tag]
    func encryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // combined already has format: nonce + ciphertext + tag
        return combined
    }

    /// Decrypt binary data where IV is prepended to ciphertext
    func decryptData(_ encryptedData: Data, using key: SymmetricKey) throws -> Data {
        // Data format: [12-byte IV][ciphertext][16-byte tag]
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Verification

    /// Verify a password by attempting to decrypt a test payload
    func verifyKey(_ key: SymmetricKey, with testPayload: EncryptedPayload) -> Bool {
        do {
            _ = try decrypt(testPayload, using: key)
            return true
        } catch {
            return false
        }
    }

    /// Create a test payload for password verification
    func createTestPayload(using key: SymmetricKey) throws -> EncryptedPayload {
        return try encrypt("test", using: key)
    }
}

// MARK: - Data Extension

extension Data {
    init?(nonce: AES.GCM.Nonce) {
        self = nonce.withUnsafeBytes { Data($0) }
    }
}
