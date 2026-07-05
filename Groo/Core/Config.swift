//
//  Config.swift
//  Groo
//
//  Centralized configuration for URLs and settings.
//  Debug builds use local servers, Release uses production.
//

import Foundation
import os

enum Config {
    /// Resolve a UserDefaults URL override. A present-but-unparseable override
    /// is a dev configuration error: log it and assert instead of silently
    /// falling through to the default URL. `defaults` is injectable so tests
    /// drive resolution with a suite-named UserDefaults, never `.standard`.
    static func overrideURL(forKey key: String, in defaults: UserDefaults = .standard) -> URL? {
        guard let override = defaults.string(forKey: key) else {
            return nil
        }
        guard let url = URL(string: override) else {
            Log.network.error("Invalid \(key, privacy: .public) override \"\(override, privacy: .public)\"; falling back to default")
            assertionFailure("Invalid \(key) override: \(override)")
            return nil
        }
        return url
    }
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
        if let url = overrideURL(forKey: "padAPIBaseURL") {
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
        if let url = overrideURL(forKey: "accountsAPIBaseURL") {
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
        if let url = overrideURL(forKey: "passAPIBaseURL") {
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
        if let url = overrideURL(forKey: "ethereumRPCURL") {
            return url
        }
        return URL(string: "https://eth.llamarpc.com")!
    }

    /// Blockscout API for token discovery. Override via UserDefaults "blockscoutBaseURL".
    static var blockscoutBaseURL: URL {
        if let url = overrideURL(forKey: "blockscoutBaseURL") {
            return url
        }
        return URL(string: "https://eth.blockscout.com/api")!
    }

    // MARK: - CoinGecko

    /// CoinGecko API base URL. Override via UserDefaults "coinGeckoBaseURL"
    /// (UI tests register a dead-end override so price lookups never leave
    /// the machine).
    static var coinGeckoBaseURL: URL {
        if let url = overrideURL(forKey: "coinGeckoBaseURL") {
            return url
        }
        return URL(string: "https://api.coingecko.com/api/v3")!
    }
}
