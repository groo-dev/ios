//
//  SharedCrypto.swift
//  Groo
//
//  Shared cryptographic functions for app and extensions.
//  AES-256-GCM decryption for Pass vault.
//

import CryptoKit
import Foundation

enum SharedCryptoError: Error {
    case decryptionFailed
    case invalidBase64
}

enum SharedCrypto {
    /// Decrypt vault data using AES-256-GCM
    /// - Parameters:
    ///   - encryptedData: The encrypted vault data (ciphertext + tag)
    ///   - iv: The initialization vector (base64 encoded)
    ///   - key: The symmetric encryption key
    /// - Returns: Decrypted vault JSON string
    static func decryptVault(encryptedData: Data, iv: String, key: SymmetricKey) throws -> String {
        guard let ivData = Data(base64Encoded: iv) else {
            throw SharedCryptoError.invalidBase64
        }

        // Reconstruct combined data (nonce + ciphertext + tag)
        var combined = Data(ivData)
        combined.append(encryptedData)

        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decrypted, encoding: .utf8) else {
            throw SharedCryptoError.decryptionFailed
        }

        return plaintext
    }
}
