//
//  SharedPadCrypto.swift
//  Groo
//
//  AES-256-GCM decryption for Pad payloads: base64 "ciphertext+tag" with a
//  separate base64 IV — exactly the format CryptoService.encrypt produces.
//  Compiled into the app (for tests) and the Widget/Keyboard extensions,
//  which previously carried duplicate copies inside ExtensionHelper.swift.
//

import CryptoKit
import Foundation

enum SharedPadCrypto {
    struct EncryptedPayload: Codable {
        let ciphertext: String
        let iv: String
        let version: Int
    }

    enum DecryptError: Error {
        case malformedPayload
        case invalidUTF8
    }

    /// Decrypt text using AES-256-GCM
    static func decrypt(_ payload: EncryptedPayload, using key: SymmetricKey) throws -> String {
        guard let ciphertextData = Data(base64Encoded: payload.ciphertext),
              let ivData = Data(base64Encoded: payload.iv) else {
            throw DecryptError.malformedPayload
        }

        let nonce = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData.dropLast(16), tag: ciphertextData.suffix(16))
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        guard let text = String(data: decryptedData, encoding: .utf8) else {
            throw DecryptError.invalidUTF8
        }
        return text
    }
}
