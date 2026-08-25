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
    @Test func oauthUsesGrooWorkspaceIssuer() {
        #expect(GrooAuthFactory.makeConfig().issuer == URL(string: "https://me.groo.dev"))
    }

    /// Every requested scope must sit inside some application registered for
    /// bundle `dev.groo.ios`. Verified against live `tenant-v1` on 2026-08-25,
    /// that is four applications — Azan, Drive, Pad and Pass — and their union
    /// is the set below.
    ///
    /// This is a sign-in-or-not guard, not a tidiness one. `runtime`'s authorize
    /// endpoint rejects the WHOLE request with `invalid_scope` when any single
    /// requested scope falls outside every named application's ceiling
    /// (`runtime/api/src/routes/oauth.ts:190`). One stray scope costs sign-in
    /// entirely; it does not degrade to a partial grant.
    ///
    /// `tasks:read`/`tasks:write` were requested here until 2026-08-25 despite
    /// this app having no Tasks feature, and no application registered for this
    /// bundle allows them.
    @Test func requestsNoScopeOutsideTheApplicationsThisBundleIsRegisteredFor() {
        let registered: Set<String> = [
            "openid", "profile", "email", "offline_access", "accounts:profile",
            "azan:read", "azan:write",
            "drive:read", "drive:write",
            "pad:read", "pad:write",
            "pass:read", "pass:write",
        ]

        let requested = Set(GrooAuthFactory.makeConfig().scopes)

        #expect(requested.subtracting(registered).isEmpty)
    }

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
