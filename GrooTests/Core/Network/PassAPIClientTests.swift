//
//  PassAPIClientTests.swift
//  GrooTests
//
//  Serialized: StubURLProtocol uses static state.
//

import Foundation
import Testing
@testable import Groo

@Suite(.serialized)
struct PassAPIClientTests {

    /// Thread-safe holder mirroring production's coupling between `tokenProvider`
    /// and `forceRefresh`: in the real app both close over `authService`, so
    /// calling `forceRefresh()` updates the state a later `tokenProvider()` call
    /// observes (see `ContentView.initializeServices()`). Two independent fixed
    /// closures wouldn't model that — the retry would never see the refreshed token.
    private final class TokenBox: @unchecked Sendable {
        private let lock = NSLock()
        private var current: String
        init(_ initial: String) { current = initial }
        var value: String {
            lock.lock(); defer { lock.unlock() }
            return current
        }
        func set(_ newValue: String) {
            lock.lock(); defer { lock.unlock() }
            current = newValue
        }
    }

    static func makeClient(
        token: String = "tok-1",
        refreshedToken: String = "tok-2"
    ) -> PassAPIClient {
        let box = TokenBox(token)
        return PassAPIClient(
            tokenProvider: { box.value },
            forceRefresh: {
                box.set(refreshedToken)
                return refreshedToken
            },
            sessionConfiguration: StubURLProtocol.stubbedConfiguration()
        )
    }

    @Test func getDecodesResponseAndSendsBearerToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault/key-info",
                                json: #"{"keySalt":"c2FsdA==","kdfIterations":1000}"#)

        let info: PassKeyInfo = try await Self.makeClient().get(PassAPIClient.Endpoint.keyInfo)

        #expect(info.kdfIterations == 1000)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func unauthorizedTriggersExactlyOneRefreshAndRetry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault/key-info", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault/key-info",
                                json: #"{"keySalt":"c2FsdA==","kdfIterations":1000}"#)

        let info: PassKeyInfo = try await Self.makeClient().get(PassAPIClient.Endpoint.keyInfo)

        #expect(info.kdfIterations == 1000)
        let requests = StubURLProtocol.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
    }

    @Test func secondUnauthorizedPropagates() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", status: 401, json: "{}")
        // last-response-repeats: the 401 sticks for the retry too

        await #expect(throws: APIError.self) {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        }
        #expect(StubURLProtocol.recordedRequests.count == 2)  // exactly one retry, no loop
    }

    @Test func conflict409SurfacesAsVersionConflict() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/vault", status: 409, json: "{}")

        await #expect {
            let _: PassVaultResponse = try await Self.makeClient().put(
                PassAPIClient.Endpoint.vault,
                body: PassVaultUpdateRequest(encryptedData: "", iv: "", expectedVersion: 1))
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 409 && message == "VERSION_CONFLICT"
        }
    }

    @Test func serverErrorMessageIsExtracted() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", status: 500,
                                json: #"{"error":"boom"}"#)

        await #expect {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 500 && message == "boom"
        }
    }

    @Test func malformedJsonIsDecodingFailure() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", json: "not json at all")

        await #expect {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        } throws: { error in
            guard case APIError.decodingFailed = error else { return false }
            return true
        }
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet])
    func transportErrorsPropagate(_ code: URLError.Code) async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", error: URLError(code))

        await #expect(throws: (any Error).self) {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        }
    }

    @Test func emptyBodyOn2xxIsDecodingFailure() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", json: "")

        await #expect(throws: (any Error).self) {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        }
    }
}
