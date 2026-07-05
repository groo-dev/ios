//
//  StockPortfolioManagerTests.swift
//  GrooTests
//
//  CRUD + load/sort semantics over an in-memory LocalStore. refreshPrices
//  reads UserDefaults.standard-backed displayCurrency — pinned via
//  withPinnedDefaults (Phase 7 helper) and restored after each use, same
//  seam StockPortfolioCurrencyTests already relies on for exchange rates.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
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

    static func stubbedYahoo() -> YahooFinanceService {
        YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    @Test func refreshPricesUpdatesCachesQuotesAndFlagsFailures() async throws {
        StubURLProtocol.reset()
        let (manager, store) = try Self.makeManager()
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 10, totalCost: 1000, date: Date(timeIntervalSince1970: 1_700_000_000))
        manager.addHolding(symbol: "MSFT", companyName: "Microsoft", exchange: "NMS")
        // MSFT stays unstubbed → dropped from quotes → failedSymbols branch
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL",
                                json: YahooFinanceServiceTests.chartJSON(price: "150.0", previousClose: "148.0"))

        await withPinnedDefaults(["displayCurrency": "USD"]) {
            await manager.refreshPrices(using: Self.stubbedYahoo())
        }

        let aapl = try #require(manager.holdings.first { $0.symbol == "AAPL" })
        #expect(aapl.currentPrice == 150)
        #expect(store.getStockHolding(symbol: "AAPL")?.cachedPrice == 150)
        #expect(manager.staleReason?.contains("MSFT") == true)
        #expect(manager.isOffline == false)
        // Single currency (USD == displayCurrency) — short-circuits to 1.0, no rate fetch
        #expect(manager.exchangeRates == ["USD": 1.0])
    }

    @Test func refreshPricesCompleteFailureWithNoCacheSurfacesError() async throws {
        StubURLProtocol.reset()
        let (manager, _) = try Self.makeManager()
        manager.addHolding(symbol: "GHOST", companyName: "Ghost Co", exchange: "NMS")
        manager.addTransaction(to: "GHOST", type: .buy, shares: 1, totalCost: 10, date: Date(timeIntervalSince1970: 1_700_000_000))
        // No stub enqueued at all → getQuotes returns empty → complete-failure branch

        await withPinnedDefaults(["displayCurrency": "USD"]) {
            await manager.refreshPrices(using: Self.stubbedYahoo())
        }

        #expect(manager.error == "Failed to load prices for GHOST — check your connection and try again")
        #expect(manager.isLoading == false)
    }

    @Test func deleteHoldingRemovesFromStoreAndList() throws {
        let (manager, store) = try Self.makeManager()
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        #expect(store.getStockHolding(symbol: "AAPL") != nil)

        manager.deleteHolding(symbol: "aapl")

        #expect(store.getStockHolding(symbol: "AAPL") == nil)
        #expect(manager.holdings.isEmpty)
    }
}
}
