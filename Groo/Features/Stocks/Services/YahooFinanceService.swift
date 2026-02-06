//
//  YahooFinanceService.swift
//  Groo
//
//  Yahoo Finance API client for stock quotes, charts, and search.
//  Includes in-memory caching and retry logic.
//

import Foundation
import os

actor YahooFinanceService {
    private let logger = Logger(subsystem: "dev.groo.ios", category: "YahooFinanceService")
    private let session: URLSession
    private let decoder: JSONDecoder

    private let chartBaseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart")!
    private let searchBaseURL = URL(string: "https://query1.finance.yahoo.com/v1/finance/search")!

    // Cache with TTL
    private var quoteCache: [String: CacheEntry<StockQuote>] = [:]
    private var chartCache: [String: CacheEntry<StockChartData>] = [:]
    private var searchCache: [String: CacheEntry<[StockSearchResult]>] = [:]
    private var rateCache: [String: CacheEntry<Double>] = [:]

    private let quoteTTL: TimeInterval = 60       // 1 minute
    private let chartTTL: TimeInterval = 300      // 5 minutes
    private let searchTTL: TimeInterval = 600     // 10 minutes
    private let rateTTL: TimeInterval = 300       // 5 minutes

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    private func withRetry<T>(maxAttempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
        var lastError: Error = YahooFinanceError.invalidResponse
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch YahooFinanceError.httpError(let code) where code == 429 {
                lastError = YahooFinanceError.httpError(429)
                let delay = pow(2.0, Double(attempt))
                logger.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                try? await Task.sleep(for: .seconds(delay))
            } catch {
                throw error
            }
        }
        throw lastError
    }

    // MARK: - Quotes

    /// Get a quote for a single symbol using the chart endpoint
    func getQuote(symbol: String) async throws -> StockQuote {
        let upper = symbol.uppercased()

        if let cached = quoteCache[upper], !cached.isExpired(ttl: quoteTTL) {
            return cached.value
        }

        return try await withRetry {
            var components = URLComponents(url: self.chartBaseURL.appendingPathComponent(upper), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "range", value: "1d"),
                URLQueryItem(name: "interval", value: "5m"),
            ]

            let (data, response) = try await self.session.data(from: components.url!)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                self.logger.error("Quote request for \(upper) failed with HTTP \(statusCode)")
                throw YahooFinanceError.httpError(statusCode)
            }

            let chartResponse = try self.decoder.decode(YahooChartResponse.self, from: data)

            guard let result = chartResponse.chart.result?.first else {
                if let err = chartResponse.chart.error {
                    throw YahooFinanceError.apiError(err.description ?? "Unknown error")
                }
                throw YahooFinanceError.symbolNotFound
            }

            let meta = result.meta
            guard let price = meta.regularMarketPrice, price > 0 else {
                throw YahooFinanceError.symbolNotFound
            }

            let previousClose = meta.previousClose ?? price
            let changePercent = previousClose > 0 ? ((price - previousClose) / previousClose) * 100 : 0

            let quote = StockQuote(
                symbol: upper,
                price: price,
                previousClose: previousClose,
                changePercent: changePercent,
                exchange: meta.exchangeName ?? "",
                currency: meta.currency ?? "USD"
            )

            self.quoteCache[upper] = CacheEntry(value: quote)
            return quote
        }
    }

    /// Get quotes for multiple symbols in parallel
    func getQuotes(symbols: [String]) async -> [String: StockQuote] {
        guard !symbols.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols {
                group.addTask {
                    let quote = try? await self.getQuote(symbol: symbol)
                    return (symbol.uppercased(), quote)
                }
            }

            var results: [String: StockQuote] = [:]
            for await (symbol, quote) in group {
                if let quote {
                    results[symbol] = quote
                }
            }
            return results
        }
    }

    // MARK: - Charts

    /// Get chart data for a symbol with a given timeframe
    func getChartData(symbol: String, timeframe: StockChartTimeframe) async throws -> StockChartData {
        let upper = symbol.uppercased()
        let cacheKey = "\(upper)_\(timeframe.rawValue)"

        if let cached = chartCache[cacheKey], !cached.isExpired(ttl: chartTTL) {
            return cached.value
        }

        return try await withRetry {
            var components = URLComponents(url: self.chartBaseURL.appendingPathComponent(upper), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "range", value: timeframe.range),
                URLQueryItem(name: "interval", value: timeframe.interval),
            ]

            let (data, response) = try await self.session.data(from: components.url!)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                self.logger.error("Chart request for \(upper) failed with HTTP \(statusCode)")
                throw YahooFinanceError.httpError(statusCode)
            }

            let chartResponse = try self.decoder.decode(YahooChartResponse.self, from: data)

            guard let result = chartResponse.chart.result?.first else {
                if let err = chartResponse.chart.error {
                    throw YahooFinanceError.apiError(err.description ?? "Unknown error")
                }
                throw YahooFinanceError.symbolNotFound
            }

            guard let timestamps = result.timestamp,
                  let closes = result.indicators.quote.first?.close else {
                return StockChartData(points: [], tradingPeriod: nil)
            }

            var points: [StockPricePoint] = []
            for (i, ts) in timestamps.enumerated() {
                if let price = closes[safe: i] ?? nil {
                    points.append(StockPricePoint(
                        timestamp: Date(timeIntervalSince1970: Double(ts)),
                        price: price
                    ))
                }
            }

            // Extract regular trading period
            var tradingPeriod: TradingPeriod?
            if let regular = result.meta.currentTradingPeriod?.regular,
               let start = regular.start, let end = regular.end {
                tradingPeriod = TradingPeriod(
                    open: Date(timeIntervalSince1970: Double(start)),
                    close: Date(timeIntervalSince1970: Double(end))
                )
            }

            let chartData = StockChartData(points: points, tradingPeriod: tradingPeriod)
            self.chartCache[cacheKey] = CacheEntry(value: chartData)
            return chartData
        }
    }

    // MARK: - Search

    /// Search for stocks by query
    func search(query: String) async throws -> [StockSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let cached = searchCache[trimmed.lowercased()], !cached.isExpired(ttl: searchTTL) {
            return cached.value
        }

        var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "quotesCount", value: "20"),
            URLQueryItem(name: "newsCount", value: "0"),
        ]

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Search request failed with HTTP \(statusCode)")
            throw YahooFinanceError.httpError(statusCode)
        }

        let searchResponse = try decoder.decode(YahooSearchResponse.self, from: data)

        let results = searchResponse.quotes.compactMap { quote -> StockSearchResult? in
            guard let symbol = quote.symbol,
                  let type = quote.quoteType,
                  type == "EQUITY" || type == "ETF" else {
                return nil
            }

            let name = quote.longname ?? quote.shortname ?? symbol
            return StockSearchResult(
                symbol: symbol,
                name: name,
                exchange: quote.exchDisp ?? "",
                type: type
            )
        }

        searchCache[trimmed.lowercased()] = CacheEntry(value: results)
        return results
    }

    // MARK: - Exchange Rates

    /// Exchange rate via Yahoo Finance currency pair (e.g. "JPYUSD=X")
    func getExchangeRate(from: String, to: String) async throws -> Double {
        guard from.uppercased() != to.uppercased() else { return 1.0 }
        let pairKey = "\(from.uppercased())\(to.uppercased())"
        if let cached = rateCache[pairKey], !cached.isExpired(ttl: rateTTL) {
            return cached.value
        }
        let quote = try await getQuote(symbol: "\(pairKey)=X")
        rateCache[pairKey] = CacheEntry(value: quote.price)
        return quote.price
    }

    /// Batch: fetch rates for multiple source currencies to a single target
    func getExchangeRates(from currencies: Set<String>, to target: String) async -> [String: Double] {
        var results: [String: Double] = [:]
        var needed: [String] = []
        let t = target.uppercased()
        for c in currencies {
            let u = c.uppercased()
            if u == t { results[u] = 1.0 }
            else if let cached = rateCache["\(u)\(t)"], !cached.isExpired(ttl: rateTTL) {
                results[u] = cached.value
            } else { needed.append(u) }
        }
        await withTaskGroup(of: (String, Double?).self) { group in
            for c in needed {
                group.addTask { (c, try? await self.getExchangeRate(from: c, to: t)) }
            }
            for await (c, rate) in group { if let rate { results[c] = rate } }
        }
        return results
    }

    /// Clear all caches
    func clearCache() {
        quoteCache.removeAll()
        chartCache.removeAll()
        searchCache.removeAll()
        rateCache.removeAll()
    }
}

// MARK: - Cache

private nonisolated struct CacheEntry<T: Sendable>: Sendable {
    let value: T
    let timestamp: Date

    init(value: T) {
        self.value = value
        self.timestamp = Date()
    }

    func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}

// MARK: - Errors

nonisolated enum YahooFinanceError: Error, LocalizedError {
    case httpError(Int)
    case invalidResponse
    case apiError(String)
    case symbolNotFound

    nonisolated var errorDescription: String? {
        switch self {
        case .httpError(let code): "Request failed (HTTP \(code))"
        case .invalidResponse: "Invalid response"
        case .apiError(let msg): msg
        case .symbolNotFound: "Symbol not found"
        }
    }
}
