//
//  AuthServiceReauthTests.swift
//  GrooTests
//
//  A lapsed session must not throw the app back to a sign-in wall.
//

import AuthenticationServices
import Foundation
import GrooAuth
import GrooAuthUI
import Testing
@testable import Groo

@MainActor
struct AuthServiceReauthTests {
    /// GrooUser's memberwise init is internal to the SDK, so it is decoded here
    /// rather than constructed — the same route the real one takes from an ID
    /// token.
    static let user: GrooUser = try! JSONDecoder().decode(
        GrooUser.self,
        from: Data(#"{"sub":"user-1","email":"someone@groo.dev","name":"Someone"}"#.utf8)
    )

    /// Neither is reachable in these tests: the controller's state comes from the
    /// token store alone, so nothing here ever goes to the network. Both throw
    /// rather than returning empty, so a test that unexpectedly starts making
    /// requests fails instead of quietly passing against a stub.
    struct UnreachableTransport: HTTPTransporting {
        struct NotExpected: Error {}
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw NotExpected() }
        func sendWithoutFollowingRedirects(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw NotExpected() }
    }

    struct UnreachableWebAuth: WebAuthenticating {
        struct NotExpected: Error {}
        func authenticate(url: URL, callbackScheme: String, anchor: ASPresentationAnchor) async throws -> URL {
            throw NotExpected()
        }
    }

    static func liveTokens() -> StoredTokens {
        StoredTokens(
            accessToken: "access", refreshToken: "refresh", tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            idToken: nil, scope: "openid", user: user
        )
    }

    /// Builds an AuthService over `store` and waits for the controller's first
    /// state to land. Without the wait every assertion would read the
    /// still-loading defaults and pass for the wrong reason.
    static func makeService(store: InMemoryTokenStore) async throws -> AuthService {
        let config = GrooAuthConfig(
            issuer: URL(string: "https://example.invalid")!,
            clientId: "test-client",
            redirectURI: "groo-test://callback",
            scopes: ["openid"],
            keychainService: "AuthServiceReauthTests"
        )
        let session = GrooAuthSession(
            config: config,
            tokenStore: store,
            transport: UnreachableTransport(),
            webAuthenticator: UnreachableWebAuth()
        )
        let service = AuthService(controller: GrooAuthController(session: session))

        for _ in 0..<200 where service.isLoading {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(!service.isLoading, "controller never published a state")
        return service
    }

    // MARK: - The behaviour this exists for

    /// The session lapsed; the identity survived. The shell must stay up, which
    /// means `hasKnownUser` — what ContentView gates on — stays true even though
    /// `isAuthenticated` is false.
    @Test func aLapsedSessionKeepsTheUserKnown() async throws {
        let store = InMemoryTokenStore(tokens: Self.liveTokens())
        try store.clearTokens(keeping: Self.user)   // what a refused refresh does

        let service = try await Self.makeService(store: store)

        #expect(service.requiresReauth)
        #expect(!service.isAuthenticated, "tokens are gone; this must not claim otherwise")
        #expect(service.hasKnownUser,
                "a lapsed session must not read as a stranger — the app shell is gated on this")
        #expect(service.currentUserEmail == "someone@groo.dev",
                "the banner names who to sign back in as")
    }

    /// The complement, and the reason the test above means anything: a real sign
    /// out must still be a stranger. If `hasKnownUser` were simply always true,
    /// the test above would pass while the sign-in screen became unreachable.
    @Test func arealSignOutIsNotAKnownUser() async throws {
        let service = try await Self.makeService(store: InMemoryTokenStore(tokens: nil))

        #expect(!service.hasKnownUser,
                "with no identity kept there is nobody to show the app to — sign-in must appear")
        #expect(!service.requiresReauth)
        #expect(!service.isAuthenticated)
        #expect(service.currentUserEmail == nil)
    }

    @Test func aLiveSessionIsKnownAndNeedsNoReauth() async throws {
        let service = try await Self.makeService(store: InMemoryTokenStore(tokens: Self.liveTokens()))

        #expect(service.isAuthenticated)
        #expect(service.hasKnownUser)
        #expect(!service.requiresReauth, "a healthy session must not show the banner")
    }
}
