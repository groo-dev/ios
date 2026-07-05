//
//  StockPortfolioCurrencyTests.swift
//  GrooTests
//
//  Multi-currency portfolio totals: conversion through fetched Yahoo rates,
//  and holdings with unavailable rates EXCLUDED from totals (never a silent
//  1:1) with the gap surfaced via staleReason. Rates are dyadic (2^-7) so
//  converted sums compare with ==. displayCurrency is
//  UserDefaults.standard-backed (P4 gap note) — pinned to USD and restored
//  around each test; the suite is serialized so nothing else observes the
//  temporary value.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct StockPortfolioCurrencyTests {

    static func withDisplayCurrencyUSD(_ body: () async throws -> Void) async rethrows {
        let key = "displayCurrency"
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("USD", forKey: key)
        try await body()
    }

    /// One USD holding (AAPL: 10 sh @ $150, cost $1000) and one JPY holding
    /// (7203.T: 5 sh @ ¥20,000, cost ¥50,000) — both transacted, so both
    /// count toward totals.
    static func makeEnv() throws -> (manager: StockPortfolioManager, service: YahooFinanceService) {
        let store = try InMemoryLocalStore.make()
        let manager = StockPortfolioManager(store: store)

        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 10, totalCost: 1000,
                               date: Date(timeIntervalSince1970: 1_700_000_000))
        manager.addHolding(symbol: "7203.T", companyName: "Toyota", exchange: "JPX")
        manager.addTransaction(to: "7203.T", type: .buy, shares: 5, totalCost: 50_000,
                               date: Date(timeIntervalSince1970: 1_700_000_000))

        let aapl = try #require(store.getStockHolding(symbol: "AAPL"))
        aapl.cachedPrice = 150
        let toyota = try #require(store.getStockHolding(symbol: "7203.T"))
        toyota.currency = "JPY"
        toyota.cachedPrice = 20_000
        store.saveStockChanges()
        manager.loadCachedHoldings()

        let service = YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
        return (manager, service)
    }

    @Test func totalsConvertThroughFetchedDyadicRates() async throws {
        StubURLProtocol.reset()
        try await Self.withDisplayCurrencyUSD {
            let (manager, service) = try Self.makeEnv()
            // JPY→USD at a dyadic 2^-7 = 0.0078125 → exact double sums
            StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X",
                                    json: YahooFinanceServiceTests.chartJSON(price: "0.0078125", previousClose: "0.0078125"))

            await manager.refreshExchangeRates(using: service)

            #expect(manager.exchangeRate(for: "JPY") == 0.0078125)
            #expect(manager.exchangeRate(for: "USD") == 1.0)      // same-currency short-circuit
            #expect(manager.totalValue == 1500 + 100_000 * 0.0078125)     // 2281.25
            #expect(manager.totalCostBasis == 1000 + 50_000 * 0.0078125)  // 1390.625
            #expect(manager.staleReason == nil)
        }
    }

    @Test func missingRateExcludesHoldingAndSurfacesStaleReason() async throws {
        StubURLProtocol.reset()
        try await Self.withDisplayCurrencyUSD {
            let (manager, service) = try Self.makeEnv()
            // Rate fetch fails hard (500 → no retry, no sleeps)
            StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X", status: 500, json: "{}")

            await manager.refreshExchangeRates(using: service)

            #expect(manager.exchangeRate(for: "JPY") == nil)
            // The JPY holding is EXCLUDED — a silent 1:1 conversion here
            // would inflate the portfolio by ~¥100,000-as-dollars
            #expect(manager.totalValue == 1500)
            #expect(manager.totalCostBasis == 1000)
            let reason = try #require(manager.staleReason)
            #expect(reason.contains("JPY"))
        }
    }
}
}
