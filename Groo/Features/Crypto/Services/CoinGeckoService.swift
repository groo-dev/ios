//
//  CoinGeckoService.swift
//  Groo
//
//  CoinGecko API client for price charts and token pricing.
//  Uses shared APICache for response caching and request deduplication.
//

import Foundation
import os

actor CoinGeckoService {
    private let logger = Logger(subsystem: "dev.groo.ios", category: "CoinGeckoService")
    private let decoder: JSONDecoder

    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!

    private let priceTTL: TimeInterval = 300    // 5 minutes
    private let chartTTL: TimeInterval = 900    // 15 minutes

    init() {
        self.decoder = JSONDecoder()
    }

    private func withRetry<T>(maxAttempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
        var lastError: Error = CoinGeckoError.rateLimited
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch CoinGeckoError.rateLimited {
                lastError = CoinGeckoError.rateLimited
                let delay = pow(2.0, Double(attempt))
                logger.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                try? await Task.sleep(for: .seconds(delay))
            } catch let error as APICacheError {
                if case .httpError(let code, _) = error, code == 429 {
                    lastError = CoinGeckoError.rateLimited
                    let delay = pow(2.0, Double(attempt))
                    logger.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                    try? await Task.sleep(for: .seconds(delay))
                } else if case .httpError(let code, _) = error {
                    throw CoinGeckoError.httpError(code)
                } else {
                    throw error
                }
            }
        }
        throw lastError
    }

    // MARK: - Price Charts

    /// Get market chart data for a coin
    func getMarketChart(coinId: String, days: Int, forceRefresh: Bool = false) async throws -> [PricePoint] {
        return try await withRetry {
            var components = URLComponents(url: self.baseURL.appendingPathComponent("coins/\(coinId)/market_chart"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "vs_currency", value: "usd"),
                URLQueryItem(name: "days", value: String(days))
            ]

            let data = try await APICache.shared.fetch(components.url!, ttl: self.chartTTL, forceRefresh: forceRefresh)

            let chart = try self.decoder.decode(CoinGeckoMarketChart.self, from: data)
            return chart.prices.map { entry in
                PricePoint(
                    timestamp: Date(timeIntervalSince1970: entry[0] / 1000),
                    price: entry[1]
                )
            }
        }
    }

    /// Get market chart data for an ERC-20 token by contract address
    func getContractMarketChart(contractAddress: String, days: Int, forceRefresh: Bool = false) async throws -> [PricePoint] {
        return try await withRetry {
            var components = URLComponents(url: self.baseURL.appendingPathComponent("coins/ethereum/contract/\(contractAddress)/market_chart"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "vs_currency", value: "usd"),
                URLQueryItem(name: "days", value: String(days))
            ]

            let data = try await APICache.shared.fetch(components.url!, ttl: self.chartTTL, forceRefresh: forceRefresh)

            let chart = try self.decoder.decode(CoinGeckoMarketChart.self, from: data)
            return chart.prices.map { entry in
                PricePoint(
                    timestamp: Date(timeIntervalSince1970: entry[0] / 1000),
                    price: entry[1]
                )
            }
        }
    }

    // MARK: - Token Prices

    /// Get ETH price in USD
    func getEthPrice(forceRefresh: Bool = false) async throws -> CoinGeckoSimplePrice {
        return try await withRetry {
            var components = URLComponents(url: self.baseURL.appendingPathComponent("simple/price"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "ids", value: "ethereum"),
                URLQueryItem(name: "vs_currencies", value: "usd"),
                URLQueryItem(name: "include_24hr_change", value: "true")
            ]

            let data = try await APICache.shared.fetch(components.url!, ttl: self.priceTTL, forceRefresh: forceRefresh)
            let result = try self.decoder.decode([String: CoinGeckoSimplePrice].self, from: data)

            guard let price = result["ethereum"] else {
                throw CoinGeckoError.invalidResponse
            }

            return price
        }
    }

    /// Get token prices by contract addresses on Ethereum (one per request for free tier)
    func getTokenPrices(contracts: [String], forceRefresh: Bool = false) async -> TokenPriceResult {
        guard !contracts.isEmpty else {
            return TokenPriceResult(prices: [:], isComplete: true, failedContracts: [], failureReason: nil)
        }

        var prices: [String: CoinGeckoSimplePrice] = [:]
        var failedContracts: [String] = []
        var hitRateLimit = false
        var firstError: String?

        // Free tier limits to 1 contract per request — fetch individually, skip failures
        for address in contracts {
            let key = address.lowercased()

            // If we already hit a rate limit, skip remaining without attempting
            if hitRateLimit {
                failedContracts.append(key)
                continue
            }

            do {
                try await withRetry {
                    var components = URLComponents(url: self.baseURL.appendingPathComponent("simple/token_price/ethereum"), resolvingAgainstBaseURL: false)!
                    components.queryItems = [
                        URLQueryItem(name: "contract_addresses", value: address),
                        URLQueryItem(name: "vs_currencies", value: "usd"),
                        URLQueryItem(name: "include_24hr_change", value: "true")
                    ]

                    let data = try await APICache.shared.fetch(components.url!, ttl: self.priceTTL, forceRefresh: forceRefresh)
                    let result = try self.decoder.decode([String: CoinGeckoSimplePrice].self, from: data)
                    for (addr, price) in result {
                        prices[addr.lowercased()] = price
                    }
                }
            } catch CoinGeckoError.rateLimited {
                logger.warning("Rate limited after retries — skipping remaining token price requests")
                hitRateLimit = true
                failedContracts.append(key)
                if firstError == nil { firstError = CoinGeckoError.rateLimited.localizedDescription }
            } catch {
                logger.error("Token price request for \(address) failed: \(error.localizedDescription)")
                failedContracts.append(key)
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        return TokenPriceResult(
            prices: prices,
            isComplete: failedContracts.isEmpty,
            failedContracts: failedContracts,
            failureReason: firstError
        )
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
