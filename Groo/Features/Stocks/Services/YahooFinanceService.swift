//
//  YahooFinanceService.swift
//  Groo
//
//  Yahoo Finance API client for stock quotes, charts, and search.
//  Uses shared APICache for response caching and request deduplication.
//

import Foundation
import os

actor YahooFinanceService {
    private let logger = Logger(subsystem: "dev.groo.ios", category: "YahooFinanceService")
    private let decoder: JSONDecoder

    private let chartBaseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart")!
    private let searchBaseURL = URL(string: "https://query1.finance.yahoo.com/v1/finance/search")!

    private let quoteTTL: TimeInterval = 60       // 1 minute
    private let chartTTL: TimeInterval = 300      // 5 minutes
    private let searchTTL: TimeInterval = 600     // 10 minutes

    init() {
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
            } catch let error as APICacheError {
                if case .httpError(let code, _) = error, code == 429 {
                    lastError = YahooFinanceError.httpError(429)
                    let delay = pow(2.0, Double(attempt))
                    logger.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                    try? await Task.sleep(for: .seconds(delay))
                } else if case .httpError(let code, _) = error {
                    throw YahooFinanceError.httpError(code)
                } else {
                    throw error
                }
            } catch {
                throw error
            }
        }
        throw lastError
    }

    // MARK: - Quotes

    /// Get a quote for a single symbol using the chart endpoint
    func getQuote(symbol: String, forceRefresh: Bool = false) async throws -> StockQuote {
        let upper = symbol.uppercased()

        return try await withRetry {
            var components = URLComponents(url: self.chartBaseURL.appendingPathComponent(upper), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "range", value: "1d"),
                URLQueryItem(name: "interval", value: "5m"),
            ]

            let data = try await APICache.shared.fetch(components.url!, ttl: self.quoteTTL, forceRefresh: forceRefresh)

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

            return StockQuote(
                symbol: upper,
                price: price,
                previousClose: previousClose,
                changePercent: changePercent,
                exchange: meta.exchangeName ?? "",
                currency: meta.currency ?? "USD"
            )
        }
    }

    /// Get quotes for multiple symbols in parallel
    func getQuotes(symbols: [String], forceRefresh: Bool = false) async -> [String: StockQuote] {
        guard !symbols.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols {
                group.addTask {
                    let quote = try? await self.getQuote(symbol: symbol, forceRefresh: forceRefresh)
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
    func getChartData(symbol: String, timeframe: StockChartTimeframe, forceRefresh: Bool = false) async throws -> StockChartData {
        let upper = symbol.uppercased()

        return try await withRetry {
            var components = URLComponents(url: self.chartBaseURL.appendingPathComponent(upper), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "range", value: timeframe.range),
                URLQueryItem(name: "interval", value: timeframe.interval),
            ]

            let data = try await APICache.shared.fetch(components.url!, ttl: self.chartTTL, forceRefresh: forceRefresh)

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

            return StockChartData(points: points, tradingPeriod: tradingPeriod)
        }
    }

    // MARK: - Search

    /// Search for stocks by query
    func search(query: String) async throws -> [StockSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "quotesCount", value: "20"),
            URLQueryItem(name: "newsCount", value: "0"),
        ]

        let data = try await APICache.shared.fetch(components.url!, ttl: searchTTL)

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

        return results
    }

    // MARK: - Exchange Rates

    /// Exchange rate via Yahoo Finance currency pair (e.g. "JPYUSD=X")
    func getExchangeRate(from: String, to: String, forceRefresh: Bool = false) async throws -> Double {
        guard from.uppercased() != to.uppercased() else { return 1.0 }
        let pairKey = "\(from.uppercased())\(to.uppercased())"
        let quote = try await getQuote(symbol: "\(pairKey)=X", forceRefresh: forceRefresh)
        return quote.price
    }

    /// Batch: fetch rates for multiple source currencies to a single target
    func getExchangeRates(from currencies: Set<String>, to target: String, forceRefresh: Bool = false) async -> [String: Double] {
        var results: [String: Double] = [:]
        let t = target.uppercased()
        var needed: [String] = []
        for c in currencies {
            let u = c.uppercased()
            if u == t { results[u] = 1.0 }
            else { needed.append(u) }
        }
        await withTaskGroup(of: (String, Double?).self) { group in
            for c in needed {
                group.addTask { (c, try? await self.getExchangeRate(from: c, to: t, forceRefresh: forceRefresh)) }
            }
            for await (c, rate) in group { if let rate { results[c] = rate } }
        }
        return results
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
