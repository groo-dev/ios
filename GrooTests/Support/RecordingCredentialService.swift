//
//  RecordingCredentialService.swift
//  GrooTests
//

import Foundation
@testable import Groo

final class RecordingCredentialService: CredentialIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _updates: [[PassVaultItem]] = []
    var updates: [[PassVaultItem]] {
        lock.lock(); defer { lock.unlock() }
        return _updates
    }

    func updateCredentialIdentities(from items: [PassVaultItem]) async {
        lock.lock(); defer { lock.unlock() }
        _updates.append(items)
    }

    func clearCredentialIdentities() async -> Bool { true }
}
