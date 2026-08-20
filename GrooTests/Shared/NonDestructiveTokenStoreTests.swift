//
//  NonDestructiveTokenStoreTests.swift
//  GrooTests
//

import AuthenticationServices
import Foundation
import Testing
import GrooAuth
@testable import Groo

struct NonDestructiveTokenStoreTests {

    /// Records what reached the underlying store.
    final class SpyTokenStore: TokenStoring, @unchecked Sendable {
        var stored: StoredTokens?
        var clearCallCount = 0
        var saveCallCount = 0

        func load() throws -> StoredTokens? { stored }

        func save(_ tokens: StoredTokens) throws {
            saveCallCount += 1
            stored = tokens
        }

        func clear() throws {
            clearCallCount += 1
            stored = nil
        }
    }

    private func tokens(accessToken: String = "at") -> StoredTokens {
        StoredTokens(
            accessToken: accessToken,
            refreshToken: "rt",
            tokenType: "Bearer",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            idToken: nil,
            scope: "openid",
            user: nil
        )
    }

    @Test("clear() never reaches the underlying store")
    func clearIsSuppressed() throws {
        let spy = SpyTokenStore()
        spy.stored = tokens()
        let store = NonDestructiveTokenStore(wrapping: spy)

        try store.clear()

        // An extension-side refresh rejection must not sign the user out of the
        // whole app; the app resolves sign-in state itself, with UI.
        #expect(spy.clearCallCount == 0)
        #expect(spy.stored != nil)
        #expect(try store.load() != nil)
    }

    @Test("save() passes through so a rotated refresh token is persisted")
    func savePassesThrough() throws {
        let spy = SpyTokenStore()
        let store = NonDestructiveTokenStore(wrapping: spy)

        try store.save(tokens(accessToken: "rotated"))

        // Dropping a rotated token would make the app later present one the
        // server already revoked, which revokes the family and signs the user
        // out everywhere — the exact outcome this type prevents.
        #expect(spy.saveCallCount == 1)
        #expect(spy.stored?.accessToken == "rotated")
    }

    @Test("load() passes through")
    func loadPassesThrough() throws {
        let spy = SpyTokenStore()
        spy.stored = tokens(accessToken: "existing")
        let store = NonDestructiveTokenStore(wrapping: spy)

        #expect(try store.load()?.accessToken == "existing")
    }

    @Test("a suppressed clear still leaves the tokens loadable afterwards")
    func clearThenLoad() throws {
        let spy = SpyTokenStore()
        spy.stored = tokens(accessToken: "survivor")
        let store = NonDestructiveTokenStore(wrapping: spy)

        try store.clear()

        #expect(try store.load()?.accessToken == "survivor")
    }
}

struct UnavailableWebAuthenticatorTests {
    @Test("refuses to present sign-in UI from an extension")
    func refusesToAuthenticate() async {
        let authenticator = UnavailableWebAuthenticator()

        await #expect(throws: GrooAuthError.self) {
            _ = try await authenticator.authenticate(
                url: URL(string: "https://me.groo.dev/authorize")!,
                callbackScheme: "dev.groo.ios",
                anchor: ASPresentationAnchor()
            )
        }
    }
}
