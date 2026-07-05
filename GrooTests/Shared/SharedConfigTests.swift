//
//  SharedConfigTests.swift
//  GrooTests
//
//  Pins the compile-time identifiers the app and extensions must agree on.
//  A silent typo here would disconnect app↔extension data sharing (vault,
//  pending passkeys, keychain) without any error. Test builds are Debug, so
//  the .debug variants are the pinned values.
//

import Testing
@testable import Groo

struct SharedConfigTests {
    @Test func debugIdentifiersArePinned() {
        #expect(SharedConfig.appGroupIdentifier == "group.dev.groo.ios.debug")
        #expect(SharedConfig.keychainService == "dev.groo.ios.debug")
        #expect(SharedConfig.KeychainKey.passEncryptionKey == "pass_encryption_key")
        #expect(SharedConfig.KeychainKey.passSalt == "pass_salt")
    }

    @Test func sharedAndAppConfigAgree() {
        // Config (app) and SharedConfig (app + AutoFill) must never drift —
        // they address the same keychain and App Group container.
        // (ExtensionConfig in Widget/Keyboard cannot be compile-checked from
        // tests; see the phase plan's spec-coverage notes.)
        #expect(SharedConfig.appGroupIdentifier == Config.appGroupIdentifier)
        #expect(SharedConfig.keychainService == Config.keychainService)
    }
}
