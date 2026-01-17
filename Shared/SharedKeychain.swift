//
//  SharedKeychain.swift
//  Groo
//
//  Shared keychain access for app and extensions.
//  Handles biometric-protected items in shared keychain.
//

import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum SharedKeychainError: Error {
    case itemNotFound
    case loadFailed(OSStatus)
    case invalidData
}

enum SharedKeychain {
    /// Load biometric-protected encryption key
    /// Will trigger Face ID/Touch ID prompt
    static func loadEncryptionKey(prompt: String = "Authenticate to access passwords") throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedConfig.keychainService,
            kSecAttrAccount as String: SharedConfig.KeychainKey.passEncryptionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            // Note: Don't specify kSecAttrAccessGroup - iOS uses first group from entitlements
            // which includes the team ID prefix automatically
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw SharedKeychainError.itemNotFound
        }

        guard status == errSecSuccess, let keyData = result as? Data else {
            throw SharedKeychainError.loadFailed(status)
        }

        return SymmetricKey(data: keyData)
    }

    /// Check if encryption key exists (without triggering auth)
    static func encryptionKeyExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedConfig.keychainService,
            kSecAttrAccount as String: SharedConfig.KeychainKey.passEncryptionKey,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}
