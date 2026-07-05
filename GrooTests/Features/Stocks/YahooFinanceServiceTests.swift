//
//  YahooFinanceServiceTests.swift
//  GrooTests
//
//  Quote/search/exchange-rate parsing over a stubbed APICache session,
//  plus 429 retry/backoff with recorded (never slept) delays.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct YahooFinanceServiceTests {
    static func makeService() -> YahooFinanceService {
        YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    static func chartJSON(price: String, previousClose: String, currency: String = "USD") -> String {
        #"{"chart":{"result":[{"meta":{"regularMarketPrice":\#(price),"previousClose":\#(previousClose),"exchangeName":"NMS","symbol":"AAPL","currency":"\#(currency)"},"timestamp":null,"indicators":{"quote":[]}}],"error":null}}"#
    }

    @Test func quoteParsesPriceAndComputesChangePercent() async throws {
        StubURLProtocol.reset()
        // 150 vs 200 previous close → exactly -25% (dyadic, safe to ==)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: Self.chartJSON(price: "150.0", previousClose: "200.0"))

        let quote = try await Self.makeService().getQuote(symbol: "aapl")

        #expect(quote.symbol == "AAPL")
        #expect(quote.price == 150)
        #expect(quote.previousClose == 200)
        #expect(quote.changePercent == -25)
        #expect(quote.currency == "USD")
        #expect(quote.exchange == "NMS")
    }

    @Test func missingPriceThrowsSymbolNotFound() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: Self.chartJSON(price: "null", previousClose: "null"))

        await #expect {
            _ = try await Self.makeService().getQuote(symbol: "AAPL")
        } throws: { error in
            guard case YahooFinanceError.symbolNotFound = error else { return false }
            return true
        }
    }

    @Test func apiErrorDescriptionSurfaces() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/chart/GHOST",
            json: #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#
        )

        await #expect {
            _ = try await Self.makeService().getQuote(symbol: "GHOST")
        } throws: { error in
            guard case YahooFinanceError.apiError(let message) = error else { return false }
            return message == "No data found"
        }
    }

    @Test func malformedJsonSurfacesAsDecodingError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: "not json")

        await #expect {
            _ = try await Self.makeService().getQuote(symbol: "AAPL")
        } throws: { error in
            error is DecodingError
        }
    }

    @Test func getQuotesCollectsSuccessesAndDropsFailures() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: Self.chartJSON(price: "150.0", previousClose: "200.0"))
        // MSFT is unstubbed → transport error → dropped, not propagated

        let quotes = await Self.makeService().getQuotes(symbols: ["AAPL", "MSFT"])

        #expect(Set(quotes.keys) == ["AAPL"])
        #expect(quotes["AAPL"]?.price == 150)
    }

    @Test func searchFiltersToEquitiesAndEtfsAndPrefersLongname() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/finance/search",
            json: #"{"quotes":[{"symbol":"AAPL","shortname":"Apple","longname":"Apple Inc.","exchDisp":"NASDAQ","quoteType":"EQUITY"},{"symbol":"VOO","shortname":"Vanguard S&P 500","exchDisp":"NYSEArca","quoteType":"ETF"},{"symbol":"BTC-USD","shortname":"Bitcoin","quoteType":"CRYPTOCURRENCY"},{"shortname":"NoSymbol","quoteType":"EQUITY"}]}"#
        )

        let results = try await Self.makeService().search(query: "apple")

        #expect(results.map(\.symbol) == ["AAPL", "VOO"])
        #expect(results.first?.name == "Apple Inc.")        // longname preferred
        #expect(results.last?.name == "Vanguard S&P 500")   // shortname fallback
    }

    @Test func sameCurrencyExchangeRateShortCircuitsWithoutNetwork() async throws {
        StubURLProtocol.reset()

        let rate = try await Self.makeService().getExchangeRate(from: "usd", to: "USD")

        #expect(rate == 1.0)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func exchangeRateUsesCurrencyPairChartSymbol() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X", json: Self.chartJSON(price: "0.0068", previousClose: "0.0068"))

        let rate = try await Self.makeService().getExchangeRate(from: "jpy", to: "usd")

        #expect(rate == 0.0068)
        #expect(StubURLProtocol.recordedRequests.first?.url?.path.hasSuffix("/chart/JPYUSD=X") == true)
    }

    // MARK: - 429 retry/backoff (Phase 6 fast-follow — mirrors CoinGeckoServiceTests)

    /// Records backoff delays instead of sleeping — the no-sleeps rule.
    final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _delays: [Double] = []
        var delays: [Double] { lock.lock(); defer { lock.unlock() }; return _delays }
        func record(_ delay: Double) { lock.lock(); defer { lock.unlock() }; _delays.append(delay) }
    }

    static func makeRetryService() -> (service: YahooFinanceService, sleeps: SleepRecorder) {
        let recorder = SleepRecorder()
        let cache = APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
        return (YahooFinanceService(cache: cache) { recorder.record($0) }, recorder)
    }

    @Test func rateLimitRetriesWithExponentialBackoffThenThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", status: 429, json: "{}")
        // last-response-repeats: every attempt sees 429
        let (service, sleeps) = Self.makeRetryService()

        await #expect {
            _ = try await service.getQuote(symbol: "AAPL")
        } throws: { error in
            guard case YahooFinanceError.httpError(429) = error else { return false }
            return true
        }

        // 2^0, 2^1 between three attempts — and NO terminal sleep after the
        // last failure (the pre-existing 4s hang this seam also removes)
        #expect(sleeps.delays == [1.0, 2.0])
        #expect(StubURLProtocol.recordedRequests.count == 3)   // maxAttempts
    }

    @Test func rateLimitRecoversOnLaterAttempt() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", status: 429, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL",
                                json: Self.chartJSON(price: "150.0", previousClose: "200.0"))
        let (service, sleeps) = Self.makeRetryService()

        let quote = try await service.getQuote(symbol: "AAPL")

        #expect(quote.price == 150)
        #expect(sleeps.delays == [1.0])
    }

    @Test func non429HttpErrorDoesNotRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", status: 500, json: "{}")
        let (service, sleeps) = Self.makeRetryService()

        await #expect {
            _ = try await service.getQuote(symbol: "AAPL")
        } throws: { error in
            guard case YahooFinanceError.httpError(500) = error else { return false }
            return true
        }

        #expect(sleeps.delays.isEmpty)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }
}
}
