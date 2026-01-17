//
//  SharedConfig.swift
//  Groo
//
//  Shared configuration constants for app and extensions.
//

import Foundation

enum SharedConfig {
    // MARK: - App Group

    static var appGroupIdentifier: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }

    // MARK: - Keychain

    static var keychainService: String {
        #if DEBUG
        "dev.groo.ios.debug"
        #else
        "dev.groo.ios"
        #endif
    }

    // Note: We don't specify kSecAttrAccessGroup explicitly in keychain calls.
    // iOS automatically uses the first group from entitlements with team ID prefix.

    // MARK: - Keychain Keys

    enum KeychainKey {
        static let passEncryptionKey = "pass_encryption_key"
        static let passSalt = "pass_salt"
    }
}
