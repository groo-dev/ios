//
//  AuthService.swift
//  Groo
//
//  PAT (Personal Access Token) authentication.
//  User creates PAT in accounts web UI and pastes it here.
//

import UIKit
import Foundation

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
        // Clear PAT token
        try? keychain.delete(for: KeychainService.Key.patToken)

        // Clear encryption data
        try? keychain.delete(for: KeychainService.Key.encryptionKey)
        try? keychain.delete(for: KeychainService.Key.encryptionSalt)

        isAuthenticated = false
    }

    // MARK: - Get Token

    /// Get the stored PAT token
    func getPatToken() throws -> String {
        guard let token = try? keychain.loadString(for: KeychainService.Key.patToken) else {
            throw AuthError.notAuthenticated
        }
        return token
    }
}
