//
//  CachedTokenPrice.swift
//  Groo
//
//  SwiftData model for locally cached portfolio prices.
//  Stores public CoinGecko price data per wallet for instant load on reopen.
//

import Foundation
import SwiftData

@Model
final class CachedTokenPrice {
    @Attribute(.unique) var id: String          // "eth" or lowercased contract address
    var walletAddress: String                    // which wallet this cache belongs to
    var symbol: String
    var name: String
    var balance: Double
    var priceUSD: Double
    var priceChange24h: Double
    var decimals: Int
    var contractAddress: String?                 // nil for ETH
    var updatedAt: Date

    init(
        id: String,
        walletAddress: String,
        symbol: String,
        name: String,
        balance: Double,
        priceUSD: Double,
        priceChange24h: Double,
        decimals: Int,
        contractAddress: String?,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.walletAddress = walletAddress
        self.symbol = symbol
        self.name = name
        self.balance = balance
        self.priceUSD = priceUSD
        self.priceChange24h = priceChange24h
        self.decimals = decimals
        self.contractAddress = contractAddress
        self.updatedAt = updatedAt
    }
}
