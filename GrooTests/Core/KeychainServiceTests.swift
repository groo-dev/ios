//
//  KeychainServiceTests.swift
//  GrooTests
//
//  Plain-item roundtrips against the real keychain in the hosted app
//  (unique per-test keys, always cleaned up). Biometric-protected paths
//  need enrolled biometry — deliberately untested (stable exclusion list).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct KeychainServiceTests {
    static func uniqueKey() -> String { "test.p7.\(UUID().uuidString)" }

    @Test func stringRoundtripAndOverwrite() throws {
        let keychain = KeychainService()
        let key = Self.uniqueKey()
        defer { try? keychain.delete(for: key) }

        try keychain.save("first", for: key)
        #expect(try keychain.loadString(for: key) == "first")
        try keychain.save("second", for: key)
        #expect(try keychain.loadString(for: key) == "second")
        #expect(keychain.exists(for: key))
    }

    @Test func dataRoundtrip() throws {
        let keychain = KeychainService()
        let key = Self.uniqueKey()
        defer { try? keychain.delete(for: key) }

        let blob = Data((0..<64).map { UInt8($0) })
        try keychain.save(blob, for: key)
        #expect(try keychain.load(for: key) == blob)
    }

    @Test func deleteRemovesItem() throws {
        let keychain = KeychainService()
        let key = Self.uniqueKey()
        try keychain.save("gone", for: key)
        try keychain.delete(for: key)
        #expect(!keychain.exists(for: key))
    }

    @Test func loadMissingKeyThrows() {
        let keychain = KeychainService()
        #expect(throws: (any Error).self) {
            _ = try keychain.loadString(for: Self.uniqueKey())
        }
    }
}
