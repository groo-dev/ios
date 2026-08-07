//
//  NonDestructiveTokenStore.swift
//  Groo
//
//  A `TokenStoring` decorator whose `clear()` is a logged no-op.
//

import Foundation
import os
import GrooAuth

/// Wraps the real token store so an extension can never sign the user out.
///
/// `GrooAuthSession.performRefresh()` calls `tokenStore.clear()` and publishes
/// `.signedOut` when the refresh token is rejected outright. The AutoFill
/// extension shares that Keychain item with the app, so an extension-side
/// rejection — during a 5-second passkey push, off a token it may have raced
/// another process for — would sign the user out of the entire app.
///
/// Deciding the user is signed out is not the extension's call. The app
/// discovers the real state on its next refresh and signs out properly, with UI.
///
/// `save` deliberately passes through: a rotated refresh token MUST be
/// persisted, or the app would later present one the server has already
/// revoked, and revoking a rotated token's family signs the user out everywhere
/// — the exact outcome this type exists to prevent.
final class NonDestructiveTokenStore: TokenStoring {
    private let wrapped: any TokenStoring

    init(wrapping wrapped: any TokenStoring) {
        self.wrapped = wrapped
    }

    func load() throws -> StoredTokens? {
        try wrapped.load()
    }

    func save(_ tokens: StoredTokens) throws {
        try wrapped.save(tokens)
    }

    func clear() throws {
        // Logged, never silent: a suppressed sign-out that nobody can see is
        // how the two preceding AutoFill bugs became undiagnosable.
        Log.pass.error(
            "Suppressed a token-store clear() from an extension; the app will resolve sign-in state itself"
        )
    }
}
