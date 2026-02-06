//
//  LocalStockHolding.swift
//  Groo
//
//  SwiftData model for locally cached stock holdings.
//

import Foundation
import SwiftData

@Model
final class LocalStockHolding {
    @Attribute(.unique) var symbol: String
    var companyName: String
    var exchange: String
    var currency: String = "USD"
    var cachedPrice: Double
    var cachedChangePercent: Double
    var cachedPreviousClose: Double
    var priceUpdatedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \LocalStockTransaction.holding)
    var transactions: [LocalStockTransaction]

    init(
        symbol: String,
        companyName: String,
        exchange: String,
        currency: String = "USD",
        cachedPrice: Double = 0,
        cachedChangePercent: Double = 0,
        cachedPreviousClose: Double = 0,
        priceUpdatedAt: Date? = nil,
        transactions: [LocalStockTransaction] = []
    ) {
        self.symbol = symbol
        self.companyName = companyName
        self.exchange = exchange
        self.currency = currency
        self.cachedPrice = cachedPrice
        self.cachedChangePercent = cachedChangePercent
        self.cachedPreviousClose = cachedPreviousClose
        self.priceUpdatedAt = priceUpdatedAt
        self.transactions = transactions
    }
}
