//
//  ConfigTests.swift
//  GrooTests
//
//  UserDefaults override resolution for API base URLs, driven through a
//  suite-named UserDefaults (never .standard). The invalid-override branch
//  calls assertionFailure and is untestable in a Debug test host by design.
//

import Foundation
import Testing
@testable import Groo

struct ConfigTests {
    @Test func presentValidOverrideWins() throws {
        let suiteName = "config-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://pad.override.test:9999", forKey: "padAPIBaseURL")

        let url = Config.overrideURL(forKey: "padAPIBaseURL", in: defaults)

        #expect(url == URL(string: "https://pad.override.test:9999"))
    }

    @Test func absentOverrideFallsThroughToNil() throws {
        let suiteName = "config-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(Config.overrideURL(forKey: "padAPIBaseURL", in: defaults) == nil)
    }
}
