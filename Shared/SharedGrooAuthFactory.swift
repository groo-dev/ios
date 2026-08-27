//
//  SharedGrooAuthFactory.swift
//  Groo
//
//  Moved from Groo/Core/Auth/GrooAuthConfig+iOS.swift so the AutoFill extension
//  can obtain a token. `GrooAuthFactory` keeps its name and `makeConfig()` /
//  `makeSession()` API so existing app call sites compile unchanged.
//

import AuthenticationServices
import Foundation
import os
import GrooAuth

enum GrooAuthFactory {
    /// The iOS native OAuth client (shared by debug + release; only the redirect
    /// URI/keychain service vary by build configuration).
    ///
    /// **Any one of this bundle's four client rows works, and they are
    /// interchangeable.** `runtime` resolves the full application set from the
    /// row's `bundle_id`, not from the id presented
    /// (`runtime/api/src/routes/oauth.ts:155`, `resolveRequestableApplications`),
    /// and a bundle client's `iss` is the workspace origin regardless of which
    /// sibling was presented (D8, `oauth.ts:133`). Pass is used here only because
    /// this factory is also what the AutoFill extension authenticates with.
    ///
    /// Live `tenant-v1` on 2026-08-25 — `bundle_id = 'dev.groo.ios'`:
    ///   Azan  client_6ad54e4b96837e2374d6854d3c8e9bf0
    ///   Drive client_cc0167610f120dda620ed06c055cc688
    ///   Pad   client_fe2ce7764cdeba15783f4a09ea61be83
    ///   Pass  client_9ed9353071ab140875eeb1ef32095f66
    ///
    /// The previous value, `app_8462033acb01dbfac01c1e9f1e09fe03`, belonged to
    /// the catch-all `Groo` application, which was **deleted on 2026-08-22**
    /// (`runtime/CLAUDE.md`, "The `Groo` catch-all application is DELETED") —
    /// deliberately, because it was the entitlement unit for all seven products.
    /// Its clients died with it, so every shipped build since has failed sign-in
    /// with `unknown client_id`. Do not restore it; it does not exist.
    private static let clientId = "client_9ed9353071ab140875eeb1ef32095f66"

    static func makeConfig() -> GrooAuthConfig {
        #if DEBUG
        let redirect = "dev.groo.ios.debug://oauth-callback"
        let service = "dev.groo.ios.debug"
        #else
        let redirect = "dev.groo.ios://oauth-callback"
        let service = "dev.groo.ios"
        #endif

        return GrooAuthConfig(
            issuer: URL(string: "https://me.groo.dev")!,
            clientId: clientId,
            redirectURI: redirect,
            // Confined to the applications this bundle is registered for.
            // `authorize` rejects the ENTIRE request with `invalid_scope` on any
            // scope outside every named application's ceiling
            // (`runtime/api/src/routes/oauth.ts:190`) — it does not drop the
            // stray one and grant the rest. `tasks:*` was requested here until
            // 2026-08-25 despite this app having no Tasks feature and no Tasks
            // client for this bundle. Pinned by ConfigTests.
            scopes: [
                "openid", "profile", "email", "offline_access",
                // What GrooUserButton's account screen reads and writes. Global,
                // so it is granted per request rather than recorded against one
                // application — but adding it still re-prompts every existing
                // user for consent once. There is no silent way to widen a grant.
                "accounts:profile",
                "azan:read", "azan:write",
                "drive:read", "drive:write",
                "pad:read", "pad:write",
                "pass:read", "pass:write",
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

    /// A session for extensions: reads and refreshes tokens, but can neither
    /// present sign-in UI nor sign the user out.
    ///
    /// The web authenticator throws unconditionally — an AutoFill sheet must
    /// never sprout an OAuth browser — and the token store suppresses `clear()`
    /// so an extension-side refresh rejection cannot sign the user out of the
    /// whole app.
    static func makeTokenOnlySession() -> GrooAuthSession {
        let config = makeConfig()
        return GrooAuthSession(
            config: config,
            tokenStore: NonDestructiveTokenStore(
                wrapping: KeychainTokenStore(service: config.keychainService, accessGroup: nil)
            ),
            transport: URLSessionTransport(),
            webAuthenticator: UnavailableWebAuthenticator()
        )
    }
}

/// Refuses to present sign-in UI. Extensions must never do this.
struct UnavailableWebAuthenticator: WebAuthenticating {
    func authenticate(
        url: URL,
        callbackScheme: String,
        anchor: ASPresentationAnchor
    ) async throws -> URL {
        Log.pass.error("An extension attempted to present sign-in UI; refusing")
        throw GrooAuthError.signedOut
    }
}
