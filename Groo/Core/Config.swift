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
        // Local development - use Mac hostname for real device testing
        return URL(string: "http://universe.local:13648")!
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
        return URL(string: "http://universe.local:37586")!
        #else
        return URL(string: "https://accounts.groo.dev")!
        #endif
    }

    /// Pass API base URL. Can be overridden via UserDefaults "passAPIBaseURL".
    static var passAPIBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "passAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://universe.local:13650")!
        #else
        return URL(string: "https://pass.groo.dev")!
        #endif
    }

    static var accountsWebURL: URL {
        #if DEBUG
        URL(string: "http://universe.local:37586")!
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

    // Note: We don't specify kSecAttrAccessGroup explicitly in keychain calls.
    // iOS automatically uses the first group from entitlements with team ID prefix.

    // MARK: - Ethereum (public RPC + Blockscout, no API keys needed)

    /// Public Ethereum JSON-RPC endpoint. Override via UserDefaults "ethereumRPCURL".
    static var ethereumRPCURL: URL {
        if let override = UserDefaults.standard.string(forKey: "ethereumRPCURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://eth.llamarpc.com")!
    }

    /// Blockscout API for token discovery. Override via UserDefaults "blockscoutBaseURL".
    static var blockscoutBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "blockscoutBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://eth.blockscout.com/api")!
    }

    // MARK: - CoinGecko

    static var coinGeckoBaseURL: URL {
        URL(string: "https://api.coingecko.com/api/v3")!
    }
}
