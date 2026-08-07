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

    // MARK: - Pass API

    /// Pass API base URL, mirroring `Config.passAPIBaseURL` including its
    /// UserDefaults override. Duplicated here rather than shared because
    /// `Config` lives in the app target, which extensions cannot see.
    ///
    /// The override is read from the App Group defaults, not `.standard`: an
    /// extension has its own defaults domain, so a dev override set by the app
    /// would otherwise be invisible to it.
    static var passAPIBaseURL: URL {
        let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
        if let override = defaults.string(forKey: "passAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://universe.local:13650")!
        #else
        return URL(string: "https://pass.groo.dev")!
        #endif
    }
}
