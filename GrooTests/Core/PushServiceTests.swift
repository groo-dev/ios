//
//  PushServiceTests.swift
//  GrooTests
//
//  APNs registration flows over the NotificationScheduling + keychain +
//  session + token seams: authorization, register (incl. the single
//  401-refresh retry), unregister, and notification routing.
//

import Foundation
import Testing
@testable import Groo

@MainActor
final class FakePushTokens: PushTokenProviding {
    var current = "tok-1"
    var refreshed = "tok-2"
    private(set) var refreshCount = 0
    func accessToken() async throws -> String { current }
    func forceRefresh() async throws -> String { refreshCount += 1; return refreshed }
}

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized)
struct PushServiceTests {
    static let tokenData = Data([0xCA, 0xFE, 0xBA, 0xBE])

    struct Env {
        let service: PushService
        let center: FakeNotificationCenter
        let keychain: InMemoryKeychain
        let tokens: FakePushTokens
        let registerCalls: () -> Int
    }

    static func makeEnv(authorize: Bool = true) -> Env {
        StubURLProtocol.reset()
        let center = FakeNotificationCenter()
        center.authorizationResult = .success(authorize)
        let keychain = InMemoryKeychain()
        var registerCount = 0
        let service = PushService(
            center: center, keychain: keychain,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            registerForRemoteNotifications: { registerCount += 1 })
        let tokens = FakePushTokens()
        service.authService = tokens
        return Env(service: service, center: center, keychain: keychain,
                   tokens: tokens, registerCalls: { registerCount })
    }

    @Test func initLoadsCachedTokenFromKeychain() throws {
        StubURLProtocol.reset()
        let keychain = InMemoryKeychain()
        try keychain.save("cafebabe", for: KeychainService.Key.deviceToken)
        let service = PushService(center: FakeNotificationCenter(), keychain: keychain,
                                  sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                                  registerForRemoteNotifications: {})
        #expect(service.deviceToken == "cafebabe")
        #expect(service.isRegistered)
    }

    @Test func grantedAuthorizationTriggersRemoteRegistration() async throws {
        let env = Self.makeEnv(authorize: true)
        #expect(try await env.service.requestAuthorization())
        #expect(env.registerCalls() == 1)
    }

    @Test func deniedAuthorizationDoesNotRegister() async throws {
        let env = Self.makeEnv(authorize: false)
        #expect(!(try await env.service.requestAuthorization()))
        #expect(env.registerCalls() == 0)
    }

    @Test func registerDeviceTokenPostsAndCaches() async throws {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", json: #"{"ok":true}"#)

        try await env.service.registerDeviceToken(Self.tokenData)

        #expect(env.service.deviceToken == "cafebabe")
        #expect(env.service.isRegistered)
        #expect(try env.keychain.loadString(for: KeychainService.Key.deviceToken) == "cafebabe")
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
    }

    @Test func registerRetriesExactlyOnceOn401() async throws {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", json: #"{"ok":true}"#)

        try await env.service.registerDeviceToken(Self.tokenData)

        #expect(env.tokens.refreshCount == 1)
        #expect(StubURLProtocol.recordedRequests.count == 2)
        #expect(StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
        #expect(env.service.isRegistered)
    }

    @Test func registerFailureThrowsRegistrationFailed() async {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", status: 500, json: "{}")

        await #expect(throws: PushError.self) {
            try await env.service.registerDeviceToken(Self.tokenData)
        }
    }

    @Test func unregisterClearsLocalStateEvenWithoutAuth() async throws {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", json: #"{"ok":true}"#)
        try await env.service.registerDeviceToken(Self.tokenData)
        env.service.authService = nil   // no auth → local clear only

        try await env.service.unregisterDeviceToken()

        #expect(env.service.deviceToken == nil)
        #expect(!env.service.isRegistered)
        #expect(!env.keychain.exists(for: KeychainService.Key.deviceToken))
    }

    @Test func handleRemoteNotificationRoutesSyncAction() {
        let env = Self.makeEnv()
        var syncs = 0
        env.service.onSyncRequested = { syncs += 1 }
        env.service.handleRemoteNotification(["action": "sync"])
        env.service.handleRemoteNotification(["action": "other"])
        env.service.handleRemoteNotification([:])
        #expect(syncs == 1)
    }

    @Test func handleRegistrationFailureSurfacesError() {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let env = Self.makeEnv()
        env.service.handleRegistrationFailure(Boom())
        #expect(env.service.lastRegistrationError == "boom")
        #expect(!env.service.isRegistered)
    }
}
}
