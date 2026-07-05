//
//  StockPortfolioManager.swift
//  Groo
//
//  Manages stock portfolio state, CRUD operations via SwiftData,
//  and price refresh coordination.
//

import Foundation
import os
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

    private let store: LocalStore

    /// Testing seam: inject an in-memory LocalStore. Production callers keep
    /// using the shared App Group store.
    init(store: LocalStore = .shared) {
        self.store = store
    }

    var displayCurrency: String {
        get { UserDefaults.standard.string(forKey: "displayCurrency") ?? "USD" }
        set { UserDefaults.standard.set(newValue, forKey: "displayCurrency") }
    }

    /// Rate to convert `currency` into the display currency, or nil when unavailable.
    /// Callers must not fall back to 1:1 — an unavailable rate is surfaced via `staleReason`.
    func exchangeRate(for currency: String) -> Double? {
        let upper = currency.uppercased()
        if upper == displayCurrency.uppercased() { return 1.0 }
        return exchangeRates[upper]
    }

    var hasHoldings: Bool {
        !holdings.isEmpty
    }

    private var holdingsWithTransactions: [StockHolding] {
        holdings.filter { $0.hasTransactions }
    }

    // Totals exclude holdings whose exchange rate is unavailable rather than
    // converting at a silent 1:1 — the gap is surfaced via `staleReason`.
    var totalValue: Double {
        holdingsWithTransactions.reduce(0) { total, holding in
            guard let rate = exchangeRate(for: holding.currency) else { return total }
            return total + holding.currentValue * rate
        }
    }

    var totalCostBasis: Double {
        holdingsWithTransactions.reduce(0) { total, holding in
            guard let rate = exchangeRate(for: holding.currency) else { return total }
            return total + holding.totalInvested * rate
        }
    }

    var totalGainLoss: Double {
        totalValue - totalCostBasis
    }

    var totalGainLossPercent: Double {
        guard totalCostBasis > 0 else { return 0 }
        return (totalGainLoss / totalCostBasis) * 100
    }

    var totalDayGainLoss: Double {
        holdingsWithTransactions.reduce(0) { total, holding in
            guard let rate = exchangeRate(for: holding.currency) else { return total }
            return total + (holding.dayGainLoss ?? 0) * rate
        }
    }

    var hasAnyTransactions: Bool {
        holdings.contains { $0.hasTransactions }
    }

    // MARK: - Load

    func loadCachedHoldings() {
        let stored = store.getAllStockHoldings()
        holdings = stored.map { local in
            StockHolding(
                symbol: local.symbol,
                companyName: local.companyName,
                exchange: local.exchange,
                currency: local.currency,
                currentPrice: local.cachedPrice,
                changePercent: local.cachedChangePercent,
                previousClose: local.cachedPreviousClose,
                transactions: local.transactions.compactMap { tx in
                    guard let type = TransactionType(rawValue: tx.type) else {
                        Log.stocks.error("Skipping transaction \(tx.id, privacy: .public) for \(local.symbol, privacy: .public): unknown type '\(tx.type, privacy: .public)'")
                        return nil
                    }
                    return StockTransaction(
                        id: tx.id,
                        type: type,
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

    func refreshPrices(using service: YahooFinanceService, forceRefresh: Bool = false) async {
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

        let quotes = await service.getQuotes(symbols: symbols, forceRefresh: forceRefresh)

        if quotes.isEmpty {
            // Complete failure
            if hasCached {
                isOffline = true
                staleReason = nil
            } else {
                Log.stocks.error("Price refresh failed for all symbols: \(symbols.joined(separator: ", "), privacy: .public)")
                error = "Failed to load prices for \(symbols.joined(separator: ", ")) — check your connection and try again"
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
                if let local = store.getStockHolding(symbol: sym) {
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

        store.saveStockChanges()

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
            exchangeRates = await service.getExchangeRates(from: uniqueCurrencies, to: displayCurrency, forceRefresh: forceRefresh)
        } else {
            exchangeRates = [displayCurrency: 1.0]
        }
        noteMissingExchangeRates(for: uniqueCurrencies)
    }

    func refreshExchangeRates(using service: YahooFinanceService) async {
        let uniqueCurrencies = Set(holdings.map(\.currency))
        exchangeRates = await service.getExchangeRates(from: uniqueCurrencies, to: displayCurrency)
        noteMissingExchangeRates(for: uniqueCurrencies)
    }

    /// Surface currencies whose exchange rate could not be fetched — their holdings
    /// are excluded from converted totals rather than converted at a silent 1:1.
    private func noteMissingExchangeRates(for currencies: Set<String>) {
        let target = displayCurrency.uppercased()
        let missing = currencies
            .map { $0.uppercased() }
            .filter { $0 != target && exchangeRates[$0] == nil }
            .sorted()
        guard !missing.isEmpty else { return }
        Log.stocks.error("Exchange rates unavailable for \(missing.joined(separator: ", "), privacy: .public) → \(target, privacy: .public)")
        let message = "\(missing.joined(separator: ", ")) exchange rate unavailable — totals incomplete"
        staleReason = staleReason.map { "\($0). \(message)" } ?? message
    }

    // MARK: - Add Holding (Tier 1 — Quick Add)

    func addHolding(symbol: String, companyName: String, exchange: String) {
        let upper = symbol.uppercased()
        guard store.getStockHolding(symbol: upper) == nil else { return }
        let holding = LocalStockHolding(symbol: upper, companyName: companyName, exchange: exchange)
        store.saveStockHolding(holding)
        loadCachedHoldings()
    }

    // MARK: - Transaction CRUD (Tier 2)

    func addTransaction(to symbol: String, type: TransactionType, shares: Double, totalCost: Double, date: Date) {
        guard let local = store.getStockHolding(symbol: symbol.uppercased()) else {
            Log.stocks.error("addTransaction failed: no holding found for \(symbol.uppercased(), privacy: .public)")
            error = "Could not save transaction — \(symbol.uppercased()) not found"
            return
        }
        let tx = LocalStockTransaction(type: type.rawValue, shares: shares, totalCost: totalCost, date: date)
        tx.holding = local
        local.transactions.append(tx)
        store.saveStockChanges()
        loadCachedHoldings()
    }

    func updateTransaction(id: String, type: TransactionType, shares: Double, totalCost: Double, date: Date) {
        guard let tx = store.getStockTransaction(id: id) else {
            Log.stocks.error("updateTransaction failed: no transaction found with id \(id, privacy: .public)")
            error = "Could not save changes — transaction not found"
            return
        }
        tx.type = type.rawValue
        tx.shares = shares
        tx.totalCost = totalCost
        tx.date = date
        store.saveStockChanges()
        loadCachedHoldings()
    }

    func deleteTransaction(id: String) {
        guard let tx = store.getStockTransaction(id: id) else { return }
        store.deleteStockTransaction(tx)
        loadCachedHoldings()
    }

    func deleteHolding(symbol: String) {
        guard let local = store.getStockHolding(symbol: symbol.uppercased()) else { return }
        store.deleteStockHolding(local)
        loadCachedHoldings()
    }

    // MARK: - Backup / Restore

    static func exportJSON(store: LocalStore = .shared) throws -> Data {
        let stored = store.getAllStockHoldings()
        let backup = StockBackup(
            version: 1,
            exportedAt: Date(),
            holdings: stored.map { holding in
                BackupHolding(
                    symbol: holding.symbol,
                    companyName: holding.companyName,
                    exchange: holding.exchange,
                    currency: holding.currency,
                    transactions: holding.transactions.map { tx in
                        BackupTransaction(
                            id: tx.id,
                            type: tx.type,
                            shares: tx.shares,
                            totalCost: tx.totalCost,
                            date: tx.date
                        )
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func importJSON(_ data: Data, store: LocalStore = .shared) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: StockBackup
        do {
            backup = try decoder.decode(StockBackup.self, from: data)
        } catch {
            Log.stocks.error("Stock backup import failed to decode: \(String(describing: error))")
            return 0
        }

        var imported = 0
        for holding in backup.holdings {
            let symbol = holding.symbol.uppercased()
            guard store.getStockHolding(symbol: symbol) == nil else { continue }

            let local = LocalStockHolding(
                symbol: symbol,
                companyName: holding.companyName,
                exchange: holding.exchange,
                currency: holding.currency
            )
            store.saveStockHolding(local)

            for tx in holding.transactions {
                let localTx = LocalStockTransaction(
                    id: tx.id,
                    type: tx.type,
                    shares: tx.shares,
                    totalCost: tx.totalCost,
                    date: tx.date,
                    holding: local
                )
                local.transactions.append(localTx)
            }
            store.saveStockChanges()
            imported += 1
        }
        return imported
    }
}

// MARK: - Backup Models

struct StockBackup: Codable {
    let version: Int
    let exportedAt: Date
    let holdings: [BackupHolding]
}

struct BackupHolding: Codable {
    let symbol: String
    let companyName: String
    let exchange: String
    let currency: String
    let transactions: [BackupTransaction]
}

struct BackupTransaction: Codable {
    let id: String
    let type: String
    let shares: Double
    let totalCost: Double
    let date: Date
}
