//
//  APIClientTests.swift
//  GrooTests
//
//  Generic Pad APIClient: auth-header injection, 401→forced-refresh→single
//  retry, typed decode errors, server-message extraction. (PassAPIClient
//  has its own suite.)
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct APIClientTests {
    struct EchoBody: Codable, Equatable { let value: String }
    struct OkResponse: Decodable { let ok: Bool }

    /// Thread-safe token source: `token()` returns the current token;
    /// `refresh()` swaps in the refreshed one and counts calls.
    final class TokenSource: @unchecked Sendable {
        private let lock = NSLock()
        private var current: String
        private let refreshed: String
        private var _refreshCalls = 0

        init(current: String = "tok-1", refreshed: String = "tok-2") {
            self.current = current
            self.refreshed = refreshed
        }

        var refreshCalls: Int { lock.lock(); defer { lock.unlock() }; return _refreshCalls }
        func token() -> String { lock.lock(); defer { lock.unlock() }; return current }
        func refresh() -> String {
            lock.lock(); defer { lock.unlock() }
            _refreshCalls += 1
            current = refreshed
            return current
        }
    }

    static func makeClient(tokens: TokenSource = TokenSource()) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { tokens.token() },
            forceRefresh: { tokens.refresh() }
        )
    }

    // MARK: - Header injection

    @Test func getInjectsAuthAndContentHeaders() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", json: #"{"ok":true}"#)

        let response: OkResponse = try await Self.makeClient().get("/v1/thing")

        #expect(response.ok)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func postEncodesBodyAndDecodesResponse() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/thing", json: #"{"ok":true}"#)

        let response: OkResponse = try await Self.makeClient().post("/v1/thing", body: EchoBody(value: "hi"))

        #expect(response.ok)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        let body = try JSONDecoder().decode(EchoBody.self, from: try #require(request.bodyData))
        #expect(body == EchoBody(value: "hi"))
    }

    @Test func putSendsBodyWithPutMethod() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/thing/42", json: #"{"ok":true}"#)

        let response: OkResponse = try await Self.makeClient().put("/v1/thing/42", body: EchoBody(value: "updated"))

        #expect(response.ok)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.httpMethod == "PUT")
        let body = try JSONDecoder().decode(EchoBody.self, from: try #require(request.bodyData))
        #expect(body.value == "updated")
    }

    @Test func deleteTreats2xxAsSuccessWithNoDecode() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "DELETE", pathSuffix: "/v1/thing/42", status: 204, json: "")

        try await Self.makeClient().delete("/v1/thing/42")   // must not throw

        #expect(StubURLProtocol.recordedRequests.first?.httpMethod == "DELETE")
    }

    // MARK: - 401 → forced refresh → single retry

    @Test func unauthorizedForcesRefreshAndRetriesWithNewToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", json: #"{"ok":true}"#)
        let tokens = TokenSource()

        let response: OkResponse = try await Self.makeClient(tokens: tokens).get("/v1/thing")

        #expect(response.ok)
        #expect(tokens.refreshCalls == 1)
        let requests = StubURLProtocol.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
    }

    @Test func second401PropagatesWithoutFurtherRetries() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 401, json: "{}")
        // last-response-repeats: the retry also sees 401
        let tokens = TokenSource()

        await #expect {
            let _: OkResponse = try await Self.makeClient(tokens: tokens).get("/v1/thing")
        } throws: { error in
            guard case APIError.unauthorized = error else { return false }
            return true
        }

        #expect(tokens.refreshCalls == 1)
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func refreshFailureAbortsBeforeRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 401, json: "{}")
        let client = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "tok-1" },
            forceRefresh: { throw URLError(.userCancelledAuthentication) }
        )

        await #expect(throws: URLError.self) {
            let _: OkResponse = try await client.get("/v1/thing")
        }
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func missingTokenFailsWithoutNetworkTraffic() async {
        StubURLProtocol.reset()
        // Default closures both throw .unauthorized (the production default)
        let client = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration()
        )

        await #expect {
            let _: OkResponse = try await client.get("/v1/thing")
        } throws: { error in
            guard case APIError.unauthorized = error else { return false }
            return true
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    // MARK: - Error typing

    @Test func decodeFailureSurfacesAsTypedError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", json: "not json")

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            guard case APIError.decodingFailed = error else { return false }
            return true
        }
    }

    @Test func httpErrorExtractsServerMessage() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 400, json: #"{"error":"nope"}"#)

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 400 && message == "nope"
        }
    }

    @Test func httpErrorWithoutJsonBodyHasNilMessage() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 503, json: "busy")

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 503 && message == nil
        }
    }

    @Test func transportErrorPropagatesAsURLError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", error: URLError(.timedOut))

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            // Documents actual behavior: transport errors are NOT wrapped in APIError
            (error as? URLError)?.code == .timedOut
        }
    }
}
}
