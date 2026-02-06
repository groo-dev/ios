//
//  StockPortfolioManager.swift
//  Groo
//
//  Manages stock portfolio state, CRUD operations via SwiftData,
//  and price refresh coordination.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class StockPortfolioManager {
    private(set) var holdings: [StockHolding] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var staleReason: String?
    private(set) var isOffline = false
    private(set) var error: String?
    private(set) var exchangeRates: [String: Double] = [:]

    var displayCurrency: String {
        get { UserDefaults.standard.string(forKey: "displayCurrency") ?? "USD" }
        set { UserDefaults.standard.set(newValue, forKey: "displayCurrency") }
    }

    func converted(_ value: Double, from currency: String) -> Double {
        value * (exchangeRates[currency.uppercased()] ?? 1.0)
    }

    var hasHoldings: Bool {
        !holdings.isEmpty
    }

    private var holdingsWithTransactions: [StockHolding] {
        holdings.filter { $0.hasTransactions }
    }

    var totalValue: Double {
        holdingsWithTransactions.reduce(0) { $0 + converted($1.currentValue, from: $1.currency) }
    }

    var totalCostBasis: Double {
        holdingsWithTransactions.reduce(0) { $0 + converted($1.totalInvested, from: $1.currency) }
    }

    var totalGainLoss: Double {
        totalValue - totalCostBasis
    }

    var totalGainLossPercent: Double {
        guard totalCostBasis > 0 else { return 0 }
        return (totalGainLoss / totalCostBasis) * 100
    }

    var totalDayGainLoss: Double {
        holdingsWithTransactions.reduce(0) { $0 + converted($1.dayGainLoss ?? 0, from: $1.currency) }
    }

    var hasAnyTransactions: Bool {
        holdings.contains { $0.hasTransactions }
    }

    // MARK: - Load

    func loadCachedHoldings() {
        let stored = LocalStore.shared.getAllStockHoldings()
        holdings = stored.map { local in
            StockHolding(
                symbol: local.symbol,
                companyName: local.companyName,
                exchange: local.exchange,
                currency: local.currency,
                currentPrice: local.cachedPrice,
                changePercent: local.cachedChangePercent,
                previousClose: local.cachedPreviousClose,
                transactions: local.transactions.map { tx in
                    StockTransaction(
                        id: tx.id,
                        type: TransactionType(rawValue: tx.type) ?? .buy,
                        shares: tx.shares,
                        totalCost: tx.totalCost,
                        date: tx.date
                    )
                }
            )
        }.sorted {
            // Holdings with transactions first (by value desc), then watchlist-only (by symbol asc)
            if $0.hasTransactions && $1.hasTransactions {
                return $0.currentValue > $1.currentValue
            }
            if $0.hasTransactions { return true }
            if $1.hasTransactions { return false }
            return $0.symbol < $1.symbol
        }
    }

    // MARK: - Refresh Prices

    func refreshPrices(using service: YahooFinanceService) async {
        let symbols = holdings.map(\.symbol)
        guard !symbols.isEmpty else { return }

        let hasCached = holdings.contains { $0.currentPrice > 0 }
        if hasCached {
            isRefreshing = true
        } else {
            isLoading = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        let quotes = await service.getQuotes(symbols: symbols)

        if quotes.isEmpty {
            // Complete failure
            if hasCached {
                isOffline = true
                staleReason = nil
            } else {
                error = "Failed to load prices"
            }
            return
        }

        var failedSymbols: [String] = []

        var updated = holdings
        for i in updated.indices {
            let sym = updated[i].symbol
            if let quote = quotes[sym] {
                updated[i].currentPrice = quote.price
                updated[i].changePercent = quote.changePercent
                updated[i].previousClose = quote.previousClose

                // Update SwiftData cache
                if let local = LocalStore.shared.getStockHolding(symbol: sym) {
                    local.cachedPrice = quote.price
                    local.cachedChangePercent = quote.changePercent
                    local.cachedPreviousClose = quote.previousClose
                    local.currency = quote.currency
                    local.priceUpdatedAt = Date()
                }
            } else {
                failedSymbols.append(sym)
            }
        }

        LocalStore.shared.saveStockChanges()

        withAnimation {
            holdings = updated.sorted {
                if $0.hasTransactions && $1.hasTransactions {
                    return $0.currentValue > $1.currentValue
                }
                if $0.hasTransactions { return true }
                if $1.hasTransactions { return false }
                return $0.symbol < $1.symbol
            }
        }

        if failedSymbols.isEmpty {
            staleReason = nil
            isOffline = false
        } else {
            staleReason = "Some prices failed to load (\(failedSymbols.joined(separator: ", ")))"
            isOffline = false
        }

        // Fetch exchange rates
        let uniqueCurrencies = Set(holdings.map(\.currency))
        if uniqueCurrencies != Set([displayCurrency]) {
            exchangeRates = await service.getExchangeRates(from: uniqueCurrencies, to: displayCurrency)
        } else {
            exchangeRates = [displayCurrency: 1.0]
        }
    }

    func refreshExchangeRates(using service: YahooFinanceService) async {
        let uniqueCurrencies = Set(holdings.map(\.currency))
        exchangeRates = await service.getExchangeRates(from: uniqueCurrencies, to: displayCurrency)
    }

    // MARK: - Add Holding (Tier 1 — Quick Add)

    func addHolding(symbol: String, companyName: String, exchange: String) {
        let upper = symbol.uppercased()
        guard LocalStore.shared.getStockHolding(symbol: upper) == nil else { return }
        let holding = LocalStockHolding(symbol: upper, companyName: companyName, exchange: exchange)
        LocalStore.shared.saveStockHolding(holding)
        loadCachedHoldings()
    }

    // MARK: - Transaction CRUD (Tier 2)

    func addTransaction(to symbol: String, type: TransactionType, shares: Double, totalCost: Double, date: Date) {
        guard let local = LocalStore.shared.getStockHolding(symbol: symbol.uppercased()) else { return }
        let tx = LocalStockTransaction(type: type.rawValue, shares: shares, totalCost: totalCost, date: date)
        tx.holding = local
        local.transactions.append(tx)
        LocalStore.shared.saveStockChanges()
        loadCachedHoldings()
    }

    func updateTransaction(id: String, type: TransactionType, shares: Double, totalCost: Double, date: Date) {
        guard let tx = LocalStore.shared.getStockTransaction(id: id) else { return }
        tx.type = type.rawValue
        tx.shares = shares
        tx.totalCost = totalCost
        tx.date = date
        LocalStore.shared.saveStockChanges()
        loadCachedHoldings()
    }

    func deleteTransaction(id: String) {
        guard let tx = LocalStore.shared.getStockTransaction(id: id) else { return }
        LocalStore.shared.deleteStockTransaction(tx)
        loadCachedHoldings()
    }

    func deleteHolding(symbol: String) {
        guard let local = LocalStore.shared.getStockHolding(symbol: symbol.uppercased()) else { return }
        LocalStore.shared.deleteStockHolding(local)
        loadCachedHoldings()
    }
}
