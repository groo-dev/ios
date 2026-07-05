//
//  GrooAuthConfig+iOS.swift
//  Groo
//
//  Wires the GrooAuth OAuth package to this app's concrete OAuth client,
//  redirect URIs, and Keychain configuration.
//

import Foundation
import GrooAuth

enum GrooAuthFactory {
    /// The iOS native OAuth client (shared by debug + release; only the redirect
    /// URI/keychain service vary by build configuration).
    private static let clientId = "app_8462033acb01dbfac01c1e9f1e09fe03"

    static func makeConfig() -> GrooAuthConfig {
        #if DEBUG
        let redirect = "dev.groo.ios.debug://oauth-callback"
        let service = "dev.groo.ios.debug"
        #else
        let redirect = "dev.groo.ios://oauth-callback"
        let service = "dev.groo.ios"
        #endif

        return GrooAuthConfig(
            issuer: URL(string: "https://accounts.groo.dev")!,
            clientId: clientId,
            redirectURI: redirect,
            scopes: [
                "openid", "profile", "email", "offline_access",
                "pad:read", "pad:write",
                "pass:read", "pass:write",
                "tasks:read", "tasks:write",
                "drive:read", "drive:write",
            ],
            keychainService: service,
            // Deliberately nil: omitting the access group lands items in the
            // app's default Keychain access group, which — because this app
            // and its AutoFill extension share entitlements — IS the
            // team-shared "dev.groo.ios" group. This mirrors how
            // KeychainService already shares the vault encryption key with
            // the AutoFill extension. Do not hardcode
            // "$(AppIdentifierPrefix)dev.groo.ios" here: that build-setting
            // variable is only resolved by Xcode inside entitlements files,
            // not at runtime in Swift source.
            keychainAccessGroup: nil
        )
    }

    /// Builds a fully-wired `GrooAuthSession` using the real network transport
    /// and `ASWebAuthenticationSession`-backed web authenticator.
    static func makeSession() -> GrooAuthSession {
        let config = makeConfig()
        return GrooAuthSession(
            config: config,
            tokenStore: KeychainTokenStore(service: config.keychainService, accessGroup: nil),
            transport: URLSessionTransport(),
            webAuthenticator: ASWebAuthenticator()
        )
    }
}
