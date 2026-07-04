//
//  AuthService.swift
//  Groo
//
//  PAT (Personal Access Token) authentication.
//  User creates PAT in accounts web UI and pastes it here.
//

import UIKit
import Foundation
import os

// MARK: - Types

enum AuthError: Error {
    case invalidToken
    case notAuthenticated
}

// MARK: - AuthService

@MainActor
@Observable
class AuthService {
    private(set) var isAuthenticated = false
    private(set) var isLoading = false

    private let keychain = KeychainService()

    init() {
        checkExistingSession()
    }

    // MARK: - Session Check

    private func checkExistingSession() {
        isAuthenticated = keychain.exists(for: KeychainService.Key.patToken)
    }

    // MARK: - Open Settings

    /// Open accounts settings page where user can create a PAT
    func openAccountSettings() {
        UIApplication.shared.open(Config.accountsSettingsURL)
    }

    // MARK: - Login with PAT

    /// Validate and save a PAT token
    func login(patToken: String) throws {
        let trimmed = patToken.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic validation - PAT tokens start with "groo_pat_"
        guard !trimmed.isEmpty else {
            throw AuthError.invalidToken
        }

        // Save to keychain
        try keychain.save(trimmed, for: KeychainService.Key.patToken)
        isAuthenticated = true
    }

    // MARK: - Logout

    func logout() throws {
        // A failed credential wipe must be visible, but logout itself proceeds.
        // Clear PAT token
        do {
            try keychain.delete(for: KeychainService.Key.patToken)
        } catch {
            Log.store.fault("Logout: failed to delete PAT token: \(String(describing: error), privacy: .public)")
        }

        // Clear encryption data
        do {
            try keychain.delete(for: KeychainService.Key.encryptionKey)
        } catch {
            Log.store.fault("Logout: failed to delete encryption key: \(String(describing: error), privacy: .public)")
        }
        do {
            try keychain.delete(for: KeychainService.Key.encryptionSalt)
        } catch {
            Log.store.fault("Logout: failed to delete encryption salt: \(String(describing: error), privacy: .public)")
        }

        isAuthenticated = false
    }

    // MARK: - Get Token

    /// Get the stored PAT token
    func getPatToken() throws -> String {
        do {
            return try keychain.loadString(for: KeychainService.Key.patToken)
        } catch KeychainError.itemNotFound {
            throw AuthError.notAuthenticated
        } catch {
            // A keychain fault is not "not signed in" — log and keep the real cause
            Log.store.error("Failed to load PAT token: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
