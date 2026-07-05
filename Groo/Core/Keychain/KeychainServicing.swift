//
//  KeychainServicing.swift
//  Groo
//
//  Seam over KeychainService so tests can substitute an in-memory fake
//  (the real keychain — especially biometric-protected items — is not
//  available in a test host).
//

import Foundation
import LocalAuthentication

protocol KeychainServicing: Sendable {
    func save(_ value: String, for key: String) throws
    func loadString(for key: String) throws -> String
    func save(_ data: Data, for key: String) throws
    func load(for key: String) throws -> Data
    func delete(for key: String) throws
    func exists(for key: String) -> Bool
    func saveBiometricProtected(_ data: Data, for key: String) throws
    func loadBiometricProtected(for key: String, prompt: String, context: LAContext?) throws -> Data
    func deleteBiometricProtected(for key: String) throws
    func biometricProtectedKeyExists(for key: String) -> Bool
}
