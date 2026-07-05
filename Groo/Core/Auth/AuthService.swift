//
//  AuthService.swift
//  Groo
//
//  OAuth authentication via GrooAuth ("Sign in with Groo").
//  Wraps a GrooAuthSession actor and republishes its state for SwiftUI.
//

import UIKit
import Foundation
import os
import AuthenticationServices
import GrooAuth

// MARK: - AuthService

@MainActor
@Observable
final class AuthService {
    private(set) var isAuthenticated = false
    var currentUserEmail: String?

    private let session: GrooAuthSession
    private let legacyKeychain = KeychainService()
    private var stateObservationTask: Task<Void, Never>?

    init() {
        let session = GrooAuthFactory.makeSession()
        self.session = session

        stateObservationTask = Task { [weak self] in
            guard let self else { return }
            for await state in await session.stateStream {
                self.apply(state)
            }
        }

        Task { [weak self] in
            await self?.migrateLegacyPATIfNeeded()
        }
    }

    private func apply(_ state: GrooAuthState) {
        switch state {
        case .signedOut:
            isAuthenticated = false
            currentUserEmail = nil
        case .signedIn(let user):
            isAuthenticated = true
            currentUserEmail = user.email
        }
    }

    /// One-time migration away from the old pasted-PAT flow: if a legacy
    /// `pat_token` is still in the Keychain and OAuth hasn't produced a signed-in
    /// session, the PAT is dead weight — delete it and require a fresh
    /// "Sign in with Groo".
    private func migrateLegacyPATIfNeeded() async {
        guard case .signedOut = await session.currentState() else { return }
        guard legacyKeychain.exists(for: KeychainService.Key.patToken) else { return }
        do {
            try legacyKeychain.delete(for: KeychainService.Key.patToken)
        } catch {
            Log.store.fault("Legacy PAT migration: failed to delete pat_token: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Sign in / out

    /// Presents the OAuth web sign-in flow anchored to `anchor`. On success,
    /// `isAuthenticated`/`currentUserEmail` update via `stateStream`.
    func startSignIn(anchor: ASPresentationAnchor) async throws {
        _ = try await session.signIn(presentationAnchor: anchor)
    }

    /// Signs out locally and attempts server-side revocation. Never throws —
    /// the app is always signed out locally afterward regardless of whether
    /// revocation succeeded.
    func logout() async {
        _ = await session.signOut()
    }

    // MARK: - Access token (for authenticated API calls; wired up in a later task)

    func accessToken() async throws -> String {
        try await session.accessToken()
    }
}
