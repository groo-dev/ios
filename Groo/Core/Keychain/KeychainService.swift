//
//  KeychainService.swift
//  Groo
//
//  Secure credential storage using iOS Keychain.
//

import Foundation
import Security
import LocalAuthentication

enum KeychainError: Error {
    case encodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case itemNotFound
    case biometricNotAvailable
    case accessControlCreationFailed
}

struct KeychainService {
    private let service = Config.keychainService

    // MARK: - Shared Biometric Context

    /// Shared context for biometric reuse across all KeychainService instances
    private static var sharedContext: LAContext?
    private static var contextCreatedAt: Date?
    private static let contextValidityDuration: TimeInterval = 300  // 5 minutes

    /// Pre-authenticate to enable biometric reuse for subsequent keychain calls.
    /// Call this once at app startup after PAT auth to avoid multiple Face ID prompts.
    func preAuthenticate(reason: String = "Authenticate to unlock Groo") async throws {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = Self.contextValidityDuration

        try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )

        Self.sharedContext = context
        Self.contextCreatedAt = Date()
    }

    /// Check if pre-authentication is still valid
    var isPreAuthenticated: Bool {
        guard let context = Self.sharedContext,
              let createdAt = Self.contextCreatedAt else { return false }
        return Date().timeIntervalSince(createdAt) < Self.contextValidityDuration
            && context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Get valid context (shared if available, new otherwise)
    private func getContext() -> LAContext {
        if isPreAuthenticated, let context = Self.sharedContext {
            return context
        }
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = Self.contextValidityDuration
        return context
    }

    /// Clear shared context (call on sign out)
    func clearSharedContext() {
        Self.sharedContext = nil
        Self.contextCreatedAt = nil
    }

    // MARK: - String Storage

    func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, for: key)
    }

    func loadString(for key: String) throws -> String {
        let data = try load(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    // MARK: - Data Storage

    func save(_ data: Data, for key: String) throws {
        // Delete existing item first
        try? delete(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }

        return data
    }

    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func exists(for key: String) -> Bool {
        do {
            _ = try load(for: key)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Biometric-Protected Storage (for encryption key)

    /// Save data with biometric protection (Face ID/Touch ID required to access)
    /// Uses App Group keychain access for extension sharing
    func saveBiometricProtected(_ data: Data, for key: String) throws {
        // Delete existing item first
        try? deleteBiometricProtected(for: key)

        // Create access control requiring biometric authentication
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw KeychainError.accessControlCreationFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
            // Note: Don't specify kSecAttrAccessGroup - iOS uses first group from entitlements
            // which includes the team ID prefix automatically
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Load biometric-protected data (will trigger Face ID/Touch ID prompt if no valid shared context)
    func loadBiometricProtected(for key: String, prompt: String = "Authenticate to access Pad") throws -> Data {
        let context = getContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }

        return data
    }

    /// Delete biometric-protected data
    func deleteBiometricProtected(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if biometric-protected key exists (without triggering auth)
    func biometricProtectedKeyExists(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // Returns errSecInteractionNotAllowed if item exists but needs auth
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

// MARK: - Keychain Keys

extension KeychainService {
    enum Key {
        // Authentication
        static let patToken = "pat_token"

        // Encryption (legacy)
        static let encryptionKey = "encryption_key"
        static let encryptionSalt = "encryption_salt"

        // Pad encryption key (biometric protected, shared with extensions)
        static let padEncryptionKey = "pad_encryption_key"

        // Pass encryption key and salt (biometric protected, shared with extensions)
        static let passEncryptionKey = "pass_encryption_key"
        static let passSalt = "pass_salt"

        // Push notifications
        static let deviceToken = "device_token"
    }
}
