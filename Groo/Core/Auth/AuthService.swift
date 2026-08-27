//
//  AuthService.swift
//  Groo
//
//  OAuth authentication via GrooAuth ("Sign in with Groo").
//  A facade over GrooAuthUI's GrooAuthController.
//

import UIKit
import Foundation
import os
import AuthenticationServices
import GrooAuth
import GrooAuthUI

// MARK: - AuthService

/// The app's view of "who is signed in".
///
/// The actor-to-main-actor bridge this used to do by hand now lives in
/// `GrooAuthController`, which `bt/space` had written a second time — that
/// duplication is why GrooAuthUI exists. What stays here is what is actually
/// Groo's: the token accessors that `PushService` and `WebSocketService` are
/// declared against.
///
/// The state properties forward rather than mirror, so there is one observation
/// task and one copy of the state. SwiftUI still tracks them: reading them in a
/// body reads through to the `@Observable` controller.
@MainActor
@Observable
final class AuthService {
    /// The library's observable session. Views hand it to `GrooSignInView`.
    let controller: GrooAuthController

    var isAuthenticated: Bool { controller.isSignedIn }
    var currentUserEmail: String? { controller.user?.email }

    /// True until the Keychain has been read once, which is not the same as
    /// signed out. `ContentView` shows a spinner rather than the sign-in screen
    /// while it holds.
    var isLoading: Bool { controller.isLoading }

    private var session: GrooAuthSession { controller.session }

    init() {
        controller = GrooAuthController(session: GrooAuthFactory.makeSession())
    }

    // MARK: - Sign in / out

    /// Presents the OAuth web sign-in flow anchored to `anchor`. On success,
    /// `isAuthenticated`/`currentUserEmail` update via the controller.
    func startSignIn(anchor: ASPresentationAnchor) async throws {
        _ = try await controller.signIn(presentationAnchor: anchor)
    }

    /// Signs out locally and attempts server-side revocation. Never throws —
    /// the app is always signed out locally afterward regardless of whether
    /// revocation succeeded.
    func logout() async {
        _ = await controller.signOut()
    }

    // MARK: - Access token (for authenticated API calls)

    /// Returns a valid access token, refreshing transparently if it's within
    /// 60s of expiry. Throws `GrooAuthError.signedOut` if there's no session.
    func accessToken() async throws -> String {
        try await session.accessToken()
    }

    /// Forces a token refresh (bypassing the expiry check `accessToken()`
    /// uses) and returns the new access token. Callers use this exactly once
    /// after an API call comes back `401` despite holding a token
    /// `accessToken()` considered valid, then retry the request. If the
    /// refresh itself is rejected (e.g. revoked), this throws and
    /// `isAuthenticated` flips to `false` via the controller.
    func forceRefresh() async throws -> String {
        try await session.forceRefreshAccessToken()
    }
}
