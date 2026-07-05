//
//  StockModelsTests.swift
//  GrooTests
//
//  Cost-basis math on StockHolding/StockTransaction — pure, no store, no
//  network. Fixtures use dyadic values so Double == comparisons are exact.
//

import Foundation
import Testing
@testable import Groo

struct StockModelsTests {
    static func tx(_ type: TransactionType, shares: Double, totalCost: Double) -> StockTransaction {
        StockTransaction(id: UUID().uuidString, type: type, shares: shares, totalCost: totalCost, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    static func holding(
        price: Double = 0,
        previousClose: Double = 0,
        transactions: [StockTransaction] = []
    ) -> StockHolding {
        StockHolding(
            symbol: "AAPL", companyName: "Apple", exchange: "NMS", currency: "USD",
            currentPrice: price, changePercent: 0, previousClose: previousClose,
            transactions: transactions
        )
    }

    @Test func netSharesAndInvestedAreNetOfSells() {
        let holding = Self.holding(transactions: [
            Self.tx(.buy, shares: 8, totalCost: 800),
            Self.tx(.buy, shares: 4, totalCost: 500),
            Self.tx(.sell, shares: 2, totalCost: 300),
        ])

        #expect(holding.netShares == 10)          // 12 bought - 2 sold
        #expect(holding.totalInvested == 1000)    // 1300 spent - 300 proceeds
    }

    @Test func currentValueAndGainLossFollowNetShares() {
        let holding = Self.holding(price: 150, transactions: [Self.tx(.buy, shares: 4, totalCost: 400)])

        #expect(holding.currentValue == 600)
        #expect(holding.totalGainLoss == 200)
        #expect(holding.totalGainLossPercent == 50)
    }

    @Test func watchlistOnlyHoldingHasNilGainLoss() {
        let holding = Self.holding(price: 150)

        #expect(!holding.hasTransactions)
        #expect(holding.totalGainLoss == nil)
        #expect(holding.totalGainLossPercent == nil)
        #expect(holding.dayGainLoss == nil)
    }

    @Test func gainLossPercentGuardsZeroCostBasis() {
        // Fully recouped position: invested 0 net — percent must be nil, not ∞
        let holding = Self.holding(price: 100, transactions: [
            Self.tx(.buy, shares: 4, totalCost: 400),
            Self.tx(.sell, shares: 2, totalCost: 400),
        ])

        #expect(holding.totalInvested == 0)
        #expect(holding.totalGainLossPercent == nil)
    }

    @Test func dayGainLossRequiresPreviousClose() {
        let withClose = Self.holding(price: 110, previousClose: 100, transactions: [Self.tx(.buy, shares: 2, totalCost: 200)])
        #expect(withClose.dayGainLoss == 20)

        let withoutClose = Self.holding(price: 110, previousClose: 0, transactions: [Self.tx(.buy, shares: 2, totalCost: 200)])
        #expect(withoutClose.dayGainLoss == nil)
    }

    @Test func costPerShareGuardsZeroShares() {
        #expect(Self.tx(.buy, shares: 4, totalCost: 500).costPerShare == 125)
        #expect(Self.tx(.buy, shares: 0, totalCost: 500).costPerShare == 0)
    }
}
