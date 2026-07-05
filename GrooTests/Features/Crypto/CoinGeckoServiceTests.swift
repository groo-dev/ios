//
//  CoinGeckoServiceTests.swift
//  GrooTests
//
//  Retry/backoff (recorded, not slept), 429 mapping, decode, partial failure.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct CoinGeckoServiceTests {

    /// Records backoff delays instead of sleeping — the no-sleeps rule.
    final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _delays: [Double] = []
        var delays: [Double] { lock.lock(); defer { lock.unlock() }; return _delays }
        func record(_ delay: Double) { lock.lock(); defer { lock.unlock() }; _delays.append(delay) }
    }

    static func makeService() -> (service: CoinGeckoService, sleeps: SleepRecorder) {
        let recorder = SleepRecorder()
        let cache = APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
        let service = CoinGeckoService(cache: cache) { recorder.record($0) }
        return (service, recorder)
    }

    static let ethPriceJSON = #"{"ethereum":{"usd":2000.5,"usd_24h_change":-1.2}}"#

    // MARK: - Happy-path decoding

    @Test func ethPriceDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", json: Self.ethPriceJSON)
        let (service, sleeps) = Self.makeService()

        let price = try await service.getEthPrice()

        #expect(price.usd == 2000.5)
        #expect(price.usd_24h_change == -1.2)
        #expect(sleeps.delays.isEmpty)
    }

    @Test func marketChartMapsTimestampsAndPrices() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/market_chart",
                                json: #"{"prices":[[1700000000000,2000.5],[1700000060000,2001.0]]}"#)
        let (service, _) = Self.makeService()

        let points = try await service.getMarketChart(coinId: "ethereum", days: 1)

        #expect(points.count == 2)
        #expect(points[0].timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(points[0].price == 2000.5)
        #expect(points[1].price == 2001.0)
    }

    @Test func missingEthereumKeyThrowsInvalidResponse() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", json: "{}")
        let (service, _) = Self.makeService()
        await #expect {
            _ = try await service.getEthPrice()
        } throws: { error in
            guard case CoinGeckoError.invalidResponse = error else { return false }
            return true
        }
    }

    // MARK: - Retry / backoff on 429

    @Test func rateLimitRetriesWithExponentialBackoffThenThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", status: 429, json: "{}")
        // last-response-repeats: every attempt sees 429
        let (service, sleeps) = Self.makeService()

        await #expect {
            _ = try await service.getEthPrice()
        } throws: { error in
            guard case CoinGeckoError.rateLimited = error else { return false }
            return true
        }

        #expect(sleeps.delays == [1.0, 2.0])                  // 2^0, 2^1 between 3 attempts
        #expect(StubURLProtocol.recordedRequests.count == 3)  // maxAttempts
    }

    @Test func rateLimitRecoversOnLaterAttempt() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", status: 429, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", json: Self.ethPriceJSON)
        let (service, sleeps) = Self.makeService()

        let price = try await service.getEthPrice()

        #expect(price.usd == 2000.5)
        #expect(sleeps.delays == [1.0])
    }

    @Test func non429HttpErrorDoesNotRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", status: 500, json: "{}")
        let (service, sleeps) = Self.makeService()

        await #expect {
            _ = try await service.getEthPrice()
        } throws: { error in
            guard case CoinGeckoError.httpError(500) = error else { return false }
            return true
        }

        #expect(sleeps.delays.isEmpty)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    // MARK: - Batch token prices

    @Test func emptyContractListIsCompleteWithoutRequests() async {
        StubURLProtocol.reset()
        let (service, _) = Self.makeService()
        let result = await service.getTokenPrices(contracts: [])
        #expect(result.isComplete)
        #expect(result.prices.isEmpty)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func partialFailureReportsFailedContracts() async {
        StubURLProtocol.reset()
        // Contracts fetched sequentially → FIFO: first succeeds, second 500s
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/token_price/ethereum",
                                json: #"{"0xaaa":{"usd":5.0,"usd_24h_change":0.1}}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/token_price/ethereum",
                                status: 500, json: "{}")
        let (service, _) = Self.makeService()

        let result = await service.getTokenPrices(contracts: ["0xAAA", "0xBBB"])

        #expect(result.prices["0xaaa"]?.usd == 5.0)
        #expect(result.isComplete == false)
        #expect(result.failedContracts == ["0xbbb"])
        #expect(result.failureReason != nil)
    }

    @Test func rateLimitShortCircuitsRemainingContracts() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/token_price/ethereum",
                                status: 429, json: "{}")
        // repeats: contract A exhausts 3 attempts; B and C must be skipped entirely
        let (service, sleeps) = Self.makeService()

        let result = await service.getTokenPrices(contracts: ["0xA", "0xB", "0xC"])

        #expect(result.isComplete == false)
        #expect(result.failedContracts == ["0xa", "0xb", "0xc"])
        #expect(StubURLProtocol.recordedRequests.count == 3)  // only contract A's attempts
        #expect(sleeps.delays == [1.0, 2.0])
    }
}
}
