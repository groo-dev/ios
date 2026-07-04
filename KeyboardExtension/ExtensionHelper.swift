//
//  ExtensionHelper.swift
//  Groo
//
//  Shared helper for Widget and Keyboard extensions to decrypt Pad items.
//  Retrieves encryption key from Keychain (with biometric) and decrypts items.
//

import Foundation
import CryptoKit
import Security
import SwiftData
import os

// This file is shared byte-identically between the Widget and Keyboard extensions,
// so the log category is derived from the host extension's bundle identifier.
private let logger = Logger(subsystem: "dev.groo.ios", category: Bundle.main.bundleIdentifier ?? "extension")

// MARK: - Config

enum ExtensionConfig {
    static var appGroupIdentifier: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }

    static var keychainService: String {
        #if DEBUG
        "dev.groo.ios.debug"
        #else
        "dev.groo.ios"
        #endif
    }

    static var keychainAccessGroup: String {
        appGroupIdentifier
    }
}

// MARK: - Keychain Helper

enum ExtensionKeychain {
    private static let padEncryptionKey = "pad_encryption_key"

    /// Check if encryption key exists (without triggering biometric)
    static func hasEncryptionKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ExtensionConfig.keychainService,
            kSecAttrAccount as String: padEncryptionKey,
            kSecAttrAccessGroup as String: ExtensionConfig.keychainAccessGroup,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Load encryption key (triggers biometric prompt)
    static func loadEncryptionKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ExtensionConfig.keychainService,
            kSecAttrAccount as String: padEncryptionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: ExtensionConfig.keychainAccessGroup,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecSuccess && status != errSecItemNotFound && status != errSecInteractionNotAllowed {
                logger.error("Failed to load encryption key from Keychain: OSStatus \(status)")
            }
            return nil
        }

        return SymmetricKey(data: data)
    }
}

// MARK: - Crypto Helper

enum ExtensionCrypto {
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

// MARK: - Decrypted Item for Extensions

struct ExtensionPadItem: Identifiable {
    let id: String
    let text: String
}

// MARK: - Extension Data Provider

enum ExtensionDataProvider {
    /// Load and decrypt Pad items for widget/keyboard display
    /// Returns nil if locked (no key available), empty array if no items
    static func loadDecryptedItems() -> [ExtensionPadItem]? {
        // Check if we have an encryption key
        guard let key = ExtensionKeychain.loadEncryptionKey() else {
            return nil // Locked
        }

        // Load encrypted items from SwiftData
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ExtensionConfig.appGroupIdentifier
        ) else {
            logger.fault("App Group container unavailable (\(ExtensionConfig.appGroupIdentifier)) — check App Group entitlement")
            return []
        }

        // Try to read from SwiftData
        do {
            let schema = Schema([ExtensionLocalPadItem.self])
            let config = ModelConfiguration(
                schema: schema,
                url: containerURL.appendingPathComponent("Library/Application Support/default.store")
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let descriptor = FetchDescriptor<ExtensionLocalPadItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let items = try context.fetch(descriptor)

            // Decrypt items
            var decrypted: [ExtensionPadItem] = []
            var failedCount = 0
            var firstError: Error?
            for item in items {
                do {
                    guard let encryptedJSON = item.encryptedTextJSON.data(using: .utf8) else {
                        throw ExtensionCrypto.DecryptError.malformedPayload
                    }
                    let payload = try JSONDecoder().decode(ExtensionCrypto.EncryptedPayload.self, from: encryptedJSON)
                    let text = try ExtensionCrypto.decrypt(payload, using: key)
                    decrypted.append(ExtensionPadItem(id: item.id, text: text))
                } catch {
                    failedCount += 1
                    if firstError == nil { firstError = error }
                }
            }

            if failedCount > 0 {
                let firstErrorDescription = firstError.map { String(describing: $0) } ?? "unknown"
                logger.error("\(failedCount) of \(items.count) items failed to decrypt; first error: \(firstErrorDescription)")
            }

            return decrypted
        } catch {
            logger.error("ExtensionDataProvider failed to load items: \(String(describing: error))")
            return []
        }
    }

    /// Check if Pad is locked (key not available)
    static func isLocked() -> Bool {
        !ExtensionKeychain.hasEncryptionKey()
    }
}

// MARK: - SwiftData Model for Extensions

@Model
final class ExtensionLocalPadItem {
    @Attribute(.unique) var id: String
    var encryptedTextJSON: String
    var createdAt: Date

    init(id: String, encryptedTextJSON: String, createdAt: Date) {
        self.id = id
        self.encryptedTextJSON = encryptedTextJSON
        self.createdAt = createdAt
    }
}
