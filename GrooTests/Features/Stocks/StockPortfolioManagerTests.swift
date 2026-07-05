//
//  StockPortfolioManagerTests.swift
//  GrooTests
//
//  CRUD + load/sort semantics over an in-memory LocalStore. No network:
//  refreshPrices/exchange-rate flows depend on UserDefaults.standard-backed
//  displayCurrency and are deliberately out of scope (see phase plan).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct StockPortfolioManagerTests {
    static func makeManager() throws -> (manager: StockPortfolioManager, store: LocalStore) {
        let store = try InMemoryLocalStore.make()
        return (StockPortfolioManager(store: store), store)
    }

    @Test func addHoldingUppercasesAndDeduplicates() throws {
        let (manager, store) = try Self.makeManager()

        manager.addHolding(symbol: "aapl", companyName: "Apple", exchange: "NMS")
        manager.addHolding(symbol: "AAPL", companyName: "Apple Again", exchange: "NMS")

        #expect(manager.holdings.map(\.symbol) == ["AAPL"])
        #expect(store.getStockHolding(symbol: "AAPL")?.companyName == "Apple")   // first write wins
    }

    @Test func unknownTransactionTypesAreSkippedNotGarbage() throws {
        let (manager, store) = try Self.makeManager()
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 2, totalCost: 300, date: Date(timeIntervalSince1970: 1_700_000_000))

        // A future/unknown persisted type must not decode into a wrong enum case
        let local = try #require(store.getStockHolding(symbol: "AAPL"))
        local.transactions.append(LocalStockTransaction(type: "transfer", shares: 1, totalCost: 100, holding: local))
        store.saveStockChanges()
        manager.loadCachedHoldings()

        let holding = try #require(manager.holdings.first)
        #expect(holding.transactions.count == 1)
        #expect(holding.transactions.first?.type == .buy)
    }

    @Test func sortPutsTransactedHoldingsByValueThenWatchlistAlphabetically() throws {
        let (manager, store) = try Self.makeManager()
        for symbol in ["ZZZ", "AAA", "BBB", "MMM"] {
            manager.addHolding(symbol: symbol, companyName: symbol, exchange: "X")
        }
        manager.addTransaction(to: "AAA", type: .buy, shares: 1, totalCost: 100, date: Date(timeIntervalSince1970: 1_700_000_000))
        manager.addTransaction(to: "BBB", type: .buy, shares: 1, totalCost: 100, date: Date(timeIntervalSince1970: 1_700_000_000))
        try #require(store.getStockHolding(symbol: "AAA")).cachedPrice = 100
        try #require(store.getStockHolding(symbol: "BBB")).cachedPrice = 500
        store.saveStockChanges()

        manager.loadCachedHoldings()

        // Transacted first (value desc), then watchlist-only (symbol asc)
        #expect(manager.holdings.map(\.symbol) == ["BBB", "AAA", "MMM", "ZZZ"])
    }

    @Test func addTransactionToUnknownSymbolSurfacesError() throws {
        let (manager, _) = try Self.makeManager()

        manager.addTransaction(to: "GHOST", type: .buy, shares: 1, totalCost: 100, date: Date())

        #expect(manager.error == "Could not save transaction — GHOST not found")
        #expect(manager.holdings.isEmpty)
    }

    @Test func updateAndDeleteTransactionPersist() throws {
        let (manager, store) = try Self.makeManager()
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 2, totalCost: 300, date: Date(timeIntervalSince1970: 1_700_000_000))
        let txId = try #require(store.getStockHolding(symbol: "AAPL")?.transactions.first?.id)

        manager.updateTransaction(id: txId, type: .sell, shares: 1, totalCost: 200, date: Date(timeIntervalSince1970: 1_700_000_100))
        var holding = try #require(manager.holdings.first)
        #expect(holding.transactions.first?.type == .sell)
        #expect(holding.transactions.first?.totalCost == 200)

        manager.deleteTransaction(id: txId)
        holding = try #require(manager.holdings.first)
        #expect(holding.transactions.isEmpty)
    }

    @Test func exportImportRoundtripsAndSkipsExistingHoldings() throws {
        let (source, sourceStore) = try Self.makeManager()
        source.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        source.addTransaction(to: "AAPL", type: .buy, shares: 2, totalCost: 300, date: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try StockPortfolioManager.exportJSON(store: sourceStore)

        let (_, freshStore) = try Self.makeManager()
        #expect(StockPortfolioManager.importJSON(data, store: freshStore) == 1)
        #expect(freshStore.getStockHolding(symbol: "AAPL")?.transactions.count == 1)
        // Second import: existing holdings are skipped, nothing duplicated
        #expect(StockPortfolioManager.importJSON(data, store: freshStore) == 0)
        #expect(freshStore.getStockHolding(symbol: "AAPL")?.transactions.count == 1)
    }
}
