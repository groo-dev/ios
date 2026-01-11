//
//  Config.swift
//  Groo
//
//  Centralized configuration for URLs and settings.
//  Debug builds use local servers, Release uses production.
//

import Foundation

enum Config {
    // MARK: - App Group (for extension communication)

    static var appGroupIdentifier: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }

    // MARK: - URLs

    /// Pad API base URL. Can be overridden via UserDefaults "padAPIBaseURL".
    static var padAPIBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "padAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        // Local development - update ports as needed
        return URL(string: "http://localhost:13648")!
        #else
        return URL(string: "https://pad.groo.dev")!
        #endif
    }

    /// Accounts API base URL. Can be overridden via UserDefaults "accountsAPIBaseURL".
    static var accountsAPIBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "accountsAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:37586")!
        #else
        return URL(string: "https://accounts.groo.dev")!
        #endif
    }

    static var accountsWebURL: URL {
        #if DEBUG
        URL(string: "http://localhost:37586")!
        #else
        URL(string: "https://accounts.groo.dev")!
        #endif
    }

    static var accountsSettingsURL: URL {
        accountsWebURL.appendingPathComponent("settings")
    }

    // MARK: - URL Scheme

    static var urlScheme: String {
        #if DEBUG
        "groo-ios-dev"
        #else
        "groo-ios"
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
}
