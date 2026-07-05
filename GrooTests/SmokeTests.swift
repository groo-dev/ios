//
//  SmokeTests.swift
//  GrooTests
//
//  Proves the unit test target builds, links the app, and runs.
//

import Testing
@testable import Groo

struct SmokeTests {
    @Test func appModuleIsReachable() {
        #expect(Config.keychainService.hasPrefix("dev.groo.ios"))
    }
}
