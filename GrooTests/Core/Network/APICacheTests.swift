//
//  APICacheTests.swift
//  GrooTests
//
//  Cache hit/expiry, forceRefresh, in-flight dedup, error-not-cached, clear.
//  Uses fresh APICache instances (never .shared) against StubURLProtocol.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct APICacheTests {
    static let url = URL(string: "https://api.test/prices/eth")!

    static func makeCache() -> APICache {
        APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
    }

    @Test func cacheHitWithinTtlSkipsNetwork() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        let first = try await cache.fetch(Self.url, ttl: 300)
        let second = try await cache.fetch(Self.url, ttl: 300)

        #expect(first == second)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func zeroTtlAlwaysRefetches() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":2}"#)
        let cache = Self.makeCache()

        let first = try await cache.fetch(Self.url, ttl: 0)
        let second = try await cache.fetch(Self.url, ttl: 0)

        #expect(first != second)
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func forceRefreshBypassesFreshCache() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":2}"#)
        let cache = Self.makeCache()

        _ = try await cache.fetch(Self.url, ttl: 300)
        let refreshed = try await cache.fetch(Self.url, ttl: 300, forceRefresh: true)

        #expect(refreshed == Data(#"{"v":2}"#.utf8))
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func concurrentFetchesShareOneRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        async let a = cache.fetch(Self.url, ttl: 300)
        async let b = cache.fetch(Self.url, ttl: 300)
        let (ra, rb) = try await (a, b)

        #expect(ra == rb)
        // In-flight dedup (or cache hit if the first finished first) — never 2 requests.
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func httpErrorSurfacesAndIsNotCached() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", status: 500, json: #"{"err":true}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        await #expect {
            _ = try await cache.fetch(Self.url, ttl: 300)
        } throws: { error in
            guard case APICacheError.httpError(let status, _) = error else { return false }
            return status == 500
        }

        // Failure was not cached — next fetch goes to network and succeeds
        let recovered = try await cache.fetch(Self.url, ttl: 300)
        #expect(recovered == Data(#"{"v":1}"#.utf8))
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func transportErrorPropagates() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", error: URLError(.timedOut))
        let cache = Self.makeCache()
        await #expect(throws: (any Error).self) { _ = try await cache.fetch(Self.url, ttl: 300) }
    }

    @Test func clearAllEvictsEverything() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        _ = try await cache.fetch(Self.url, ttl: 300)
        await cache.clearAll()
        _ = try await cache.fetch(Self.url, ttl: 300)

        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func clearMatchingEvictsSelectively() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/btc", json: #"{"v":9}"#)
        let btcURL = URL(string: "https://api.test/prices/btc")!
        let cache = Self.makeCache()

        _ = try await cache.fetch(Self.url, ttl: 300)
        _ = try await cache.fetch(btcURL, ttl: 300)
        await cache.clear { $0.contains("eth") }
        _ = try await cache.fetch(btcURL, ttl: 300)   // still cached — no request
        _ = try await cache.fetch(Self.url, ttl: 300) // evicted — refetches

        #expect(StubURLProtocol.recordedRequests.count == 3)
    }
}
}
