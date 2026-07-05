//
//  InMemoryKeychain.swift
//  GrooTests
//
//  Deterministic KeychainServicing fake. Biometric items never prompt.
//

import Foundation
import LocalAuthentication
@testable import Groo

final class InMemoryKeychain: KeychainServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var plain: [String: Data] = [:]
    private var biometric: [String: Data] = [:]

    func save(_ value: String, for key: String) throws {
        try save(Data(value.utf8), for: key)
    }

    func loadString(for key: String) throws -> String {
        guard let string = String(data: try load(for: key), encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    func save(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = data
    }

    func load(for key: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = plain[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func delete(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = nil  // deleting a missing key is not an error, matching the real service
    }

    func exists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return plain[key] != nil
    }

    func saveBiometricProtected(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = data
    }

    func loadBiometricProtected(for key: String, prompt: String, context: LAContext?) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = biometric[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func deleteBiometricProtected(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = nil
    }

    func biometricProtectedKeyExists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return biometric[key] != nil
    }
}
