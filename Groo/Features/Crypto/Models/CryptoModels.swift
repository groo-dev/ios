//
//  CryptoModels.swift
//  Groo
//
//  Data models for Crypto wallet feature.
//

import Foundation

// MARK: - Portfolio Models

/// A crypto asset in the user's portfolio
struct CryptoAsset: Identifiable {
    let id: String // contract address or "eth" for native ETH
    let symbol: String
    let name: String
    let balance: Double
    let price: Double
    let priceChange24h: Double
    let iconURL: URL?
    let decimals: Int
    let contractAddress: String? // nil for native ETH

    var value: Double {
        balance * price
    }
}

/// A data point for price charts
struct PricePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let price: Double
}

/// Timeframe options for price charts
enum ChartTimeframe: String, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case year = "1Y"

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }
}

// MARK: - Ethereum JSON-RPC Types

/// Generic JSON-RPC response for simple results (eth_getBalance, eth_gasPrice, etc.)
struct EthRPCResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: String?
    let error: EthRPCError?
}

struct EthRPCError: Codable {
    let code: Int
    let message: String
}

/// JSON-RPC request
struct EthRPCRequest: Codable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [AnyCodable]

    init(method: String, params: [Any] = []) {
        self.jsonrpc = "2.0"
        self.id = 1
        self.method = method
        self.params = params.map { AnyCodable($0) }
    }
}

// MARK: - Blockscout Response Types

/// Response wrapper from Blockscout API
struct BlockscoutResponse<T: Codable>: Codable {
    let message: String
    let result: T
    let status: String
}

/// Token balance from Blockscout ?module=account&action=tokenlist
struct BlockscoutTokenBalance: Codable {
    let balance: String
    let contractAddress: String
    let decimals: String
    let name: String
    let symbol: String
    let type: String // "ERC-20"
}

// MARK: - CoinGecko Response Types

/// Response from /coins/{id}/market_chart
struct CoinGeckoMarketChart: Codable {
    let prices: [[Double]] // [[timestamp, price], ...]
}

/// Response from /simple/token_price/ethereum
struct CoinGeckoSimplePrice: Codable {
    let usd: Double?
    let usd_24h_change: Double?

    enum CodingKeys: String, CodingKey {
        case usd
        case usd_24h_change
    }
}

// MARK: - Token Tracking

/// Manages per-wallet token tracking state in UserDefaults.
/// Tracking state is tri-state: `nil` = unknown (needs detection), `true` = tracked, `false` = untracked.
enum TokenTrackingManager {
    private static func key(for wallet: String) -> String {
        "trackedTokens_\(wallet.lowercased())"
    }

    private static func dict(for wallet: String) -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: key(for: wallet)) as? [String: Bool] ?? [:]
    }

    /// Returns `nil` if the token has never been classified, `true` if tracked, `false` if untracked.
    static func trackingState(for contract: String, wallet: String) -> Bool? {
        dict(for: wallet)[contract.lowercased()]
    }

    /// Persist tracking state for a token contract.
    static func setTrackingState(_ tracked: Bool, for contract: String, wallet: String) {
        var d = dict(for: wallet)
        d[contract.lowercased()] = tracked
        UserDefaults.standard.set(d, forKey: key(for: wallet))
    }

    /// Returns the set of contract addresses marked as tracked (`true`).
    static func trackedContracts(wallet: String) -> Set<String> {
        Set(dict(for: wallet).filter { $0.value }.keys)
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for JSON-RPC params
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let a = try? container.decode([AnyCodable].self) { value = a.map { $0.value } }
        else if let d = try? container.decode([String: AnyCodable].self) { value = d.mapValues { $0.value } }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case let a as [Any]: try container.encode(a.map { AnyCodable($0) })
        case let d as [String: Any]: try container.encode(d.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
