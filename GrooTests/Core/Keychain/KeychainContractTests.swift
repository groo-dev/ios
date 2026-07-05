//
//  KeychainContractTests.swift
//  GrooTests
//
//  Contract the fake must honor so PassService tests are faithful.
//

import Foundation
import Testing
@testable import Groo

struct KeychainContractTests {
    let keychain: any KeychainServicing = InMemoryKeychain()

    @Test func stringRoundtrip() throws {
        try keychain.save("sekrit", for: "k")
        #expect(try keychain.loadString(for: "k") == "sekrit")
    }

    @Test func dataRoundtripAndOverwrite() throws {
        try keychain.save(Data([1, 2, 3]), for: "k")
        try keychain.save(Data([9]), for: "k")
        #expect(try keychain.load(for: "k") == Data([9]))
    }

    @Test func loadMissingThrowsItemNotFound() {
        // KeychainError has associated values (OSStatus) so it isn't Equatable —
        // match the case with the closure form.
        #expect { try keychain.load(for: "missing") } throws: { error in
            guard case KeychainError.itemNotFound = error else { return false }
            return true
        }
    }

    @Test func deleteMissingDoesNotThrow() throws {
        try keychain.delete(for: "never-existed")
    }

    @Test func existsReflectsState() throws {
        #expect(!keychain.exists(for: "k"))
        try keychain.save("v", for: "k")
        #expect(keychain.exists(for: "k"))
        try keychain.delete(for: "k")
        #expect(!keychain.exists(for: "k"))
    }

    @Test func biometricNamespaceIsSeparate() throws {
        try keychain.saveBiometricProtected(Data([7]), for: "k")
        #expect(!keychain.exists(for: "k"))  // plain namespace unaffected
        #expect(keychain.biometricProtectedKeyExists(for: "k"))
        #expect(try keychain.loadBiometricProtected(for: "k", prompt: "test", context: nil) == Data([7]))
        try keychain.deleteBiometricProtected(for: "k")
        #expect(!keychain.biometricProtectedKeyExists(for: "k"))
    }
}
