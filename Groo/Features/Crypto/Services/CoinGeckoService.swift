//
//  CoinGeckoService.swift
//  Groo
//
//  CoinGecko API client for price charts and token pricing.
//  Includes in-memory caching to stay within free tier limits.
//

import Foundation
import os

actor CoinGeckoService {
    private let logger = Logger(subsystem: "dev.groo.ios", category: "CoinGeckoService")
    private let session: URLSession
    private let decoder: JSONDecoder

    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!

    // Cache with TTL
    private var priceCache: [String: CacheEntry<CoinGeckoSimplePrice>] = [:]
    private var chartCache: [String: CacheEntry<[PricePoint]>] = [:]

    private let priceTTL: TimeInterval = 300    // 5 minutes
    private let chartTTL: TimeInterval = 900    // 15 minutes

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Price Charts

    /// Get market chart data for a coin
    func getMarketChart(coinId: String, days: Int) async throws -> [PricePoint] {
        let cacheKey = "\(coinId)_\(days)"

        if let cached = chartCache[cacheKey], !cached.isExpired(ttl: chartTTL) {
            return cached.value
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("coins/\(coinId)/market_chart"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: String(days))
        ]

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Market chart request failed with HTTP \(statusCode)")
            throw statusCode == 429 ? CoinGeckoError.rateLimited : CoinGeckoError.httpError(statusCode)
        }

        let chart = try decoder.decode(CoinGeckoMarketChart.self, from: data)
        let points = chart.prices.map { entry in
            PricePoint(
                timestamp: Date(timeIntervalSince1970: entry[0] / 1000),
                price: entry[1]
            )
        }

        chartCache[cacheKey] = CacheEntry(value: points)
        return points
    }

    /// Get market chart data for an ERC-20 token by contract address
    func getContractMarketChart(contractAddress: String, days: Int) async throws -> [PricePoint] {
        let cacheKey = "contract_\(contractAddress.lowercased())_\(days)"

        if let cached = chartCache[cacheKey], !cached.isExpired(ttl: chartTTL) {
            return cached.value
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("coins/ethereum/contract/\(contractAddress)/market_chart"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: String(days))
        ]

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Contract chart request for \(contractAddress) failed with HTTP \(statusCode)")
            throw statusCode == 429 ? CoinGeckoError.rateLimited : CoinGeckoError.httpError(statusCode)
        }

        let chart = try decoder.decode(CoinGeckoMarketChart.self, from: data)
        let points = chart.prices.map { entry in
            PricePoint(
                timestamp: Date(timeIntervalSince1970: entry[0] / 1000),
                price: entry[1]
            )
        }

        chartCache[cacheKey] = CacheEntry(value: points)
        return points
    }

    // MARK: - Token Prices

    /// Get ETH price in USD
    func getEthPrice() async throws -> CoinGeckoSimplePrice {
        let cacheKey = "ethereum"

        if let cached = priceCache[cacheKey], !cached.isExpired(ttl: priceTTL) {
            return cached.value
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("simple/price"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ids", value: "ethereum"),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true")
        ]

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("ETH price request failed with HTTP \(statusCode)")
            throw statusCode == 429 ? CoinGeckoError.rateLimited : CoinGeckoError.httpError(statusCode)
        }

        let result = try decoder.decode([String: CoinGeckoSimplePrice].self, from: data)

        guard let price = result["ethereum"] else {
            throw CoinGeckoError.invalidResponse
        }

        priceCache[cacheKey] = CacheEntry(value: price)
        return price
    }

    /// Get token prices by contract addresses on Ethereum (one per request for free tier)
    func getTokenPrices(contracts: [String]) async throws -> [String: CoinGeckoSimplePrice] {
        guard !contracts.isEmpty else { return [:] }

        var prices: [String: CoinGeckoSimplePrice] = [:]

        // Free tier limits to 1 contract per request — fetch individually, skip failures
        for address in contracts {
            let key = address.lowercased()

            // Check cache first
            if let cached = priceCache[key], !cached.isExpired(ttl: priceTTL) {
                prices[key] = cached.value
                continue
            }

            do {
                var components = URLComponents(url: baseURL.appendingPathComponent("simple/token_price/ethereum"), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "contract_addresses", value: address),
                    URLQueryItem(name: "vs_currencies", value: "usd"),
                    URLQueryItem(name: "include_24hr_change", value: "true")
                ]

                let (data, response) = try await session.data(from: components.url!)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    logger.error("Token price request for \(address) failed with HTTP \(statusCode)")
                    if statusCode == 429 {
                        logger.warning("Rate limited — stopping remaining token price requests")
                        break
                    }
                    continue
                }

                let result = try decoder.decode([String: CoinGeckoSimplePrice].self, from: data)
                for (addr, price) in result {
                    let normalizedKey = addr.lowercased()
                    prices[normalizedKey] = price
                    priceCache[normalizedKey] = CacheEntry(value: price)
                }
            } catch {
                logger.error("Token price request for \(address) failed: \(error.localizedDescription)")
                continue
            }
        }

        return prices
    }

    /// Clear all caches
    func clearCache() {
        priceCache.removeAll()
        chartCache.removeAll()
    }
}

// MARK: - Cache

private struct CacheEntry<T> {
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

enum CoinGeckoError: Error, LocalizedError {
    case httpError(Int)
    case rateLimited
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited: "CoinGecko rate limit reached — try again shortly"
        case .httpError(let code): "Price data request failed (HTTP \(code))"
        case .invalidResponse: "Invalid price data"
        }
    }
}
