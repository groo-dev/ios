//
//  StocksViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Stocks views over a seeded
//  in-memory StockPortfolioManager (P6 seeding pattern) with pinned
//  displayCurrency and a stubbed Yahoo service for exchange rates.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct StocksViewSnapshotTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func stubbedYahoo() -> YahooFinanceService {
        YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    /// AAPL (USD, priced 150 on 10 shares @100) + Toyota (JPY) — the P6
    /// currency-suite shape, dyadic numbers so totals are exact.
    static func seededManager() async throws -> StockPortfolioManager {
        StubURLProtocol.reset()
        let store = try InMemoryLocalStore.make()
        let manager = StockPortfolioManager(store: store)
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 10, totalCost: 1000, date: Self.fixedDate)
        manager.addHolding(symbol: "7203.T", companyName: "Toyota", exchange: "JPX")
        manager.addTransaction(to: "7203.T", type: .buy, shares: 50, totalCost: 50_000, date: Self.fixedDate)
        let aapl = try #require(store.getStockHolding(symbol: "AAPL"))
        aapl.cachedPrice = 150
        let toyota = try #require(store.getStockHolding(symbol: "7203.T"))
        // LocalStockHolding.currency defaults to "USD" — without setting this
        // explicitly (per the P6 pattern in StockPortfolioCurrencyTests),
        // Toyota's value would never be converted and the JPY stub below
        // would go unexercised.
        toyota.currency = "JPY"
        toyota.cachedPrice = 2000
        store.saveStockChanges()
        manager.loadCachedHoldings()
        // JPY→USD at a dyadic 2^-7 so converted totals are exact doubles
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X",
                                json: YahooFinanceServiceTests.chartJSON(price: "0.0078125", previousClose: "0.0078125"))
        await manager.refreshExchangeRates(using: Self.stubbedYahoo())
        return manager
    }

    static func holding(transactions: [StockTransaction]) -> StockHolding {
        StockHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS", currency: "USD",
                     currentPrice: 150, changePercent: 1.25, previousClose: 148.15,
                     transactions: transactions)
    }

    static func stockPoints() -> [StockPricePoint] {
        (0..<26).map {
            StockPricePoint(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 900),
                            price: 148 + Double($0) * 0.25)
        }
    }

    // MARK: - Pure fixtures

    @Test func stockPriceChartVariants() {
        let points = Self.stockPoints()
        let period = TradingPeriod(open: Date(timeIntervalSince1970: 1_700_000_000),
                                   close: Date(timeIntervalSince1970: 1_700_023_400))
        assertViewSnapshot(
            of: StockPriceChartView(data: points, isLoading: false, isPositive: true,
                                    errorMessage: nil, currencyCode: "USD", timeframe: .day,
                                    tradingPeriod: period, selectedPoint: .constant(nil)).padding(),
            named: "day-positive", size: CGSize(width: 402, height: 320))
        assertViewSnapshot(
            of: StockPriceChartView(data: points.reversed(), isLoading: false, isPositive: false,
                                    errorMessage: nil, currencyCode: "JPY", timeframe: .week,
                                    tradingPeriod: nil, selectedPoint: .constant(nil)).padding(),
            named: "week-negative-jpy", size: CGSize(width: 402, height: 320))
        assertViewSnapshot(
            of: StockPriceChartView(data: [], isLoading: false, isPositive: true,
                                    errorMessage: "No chart data", currencyCode: "USD", timeframe: .day,
                                    tradingPeriod: nil, selectedPoint: .constant(nil)).padding(),
            named: "error", size: CGSize(width: 402, height: 320))
        ViewRender.assertRenders(
            StockPriceChartView(data: [], isLoading: true, isPositive: true,
                                errorMessage: nil, currencyCode: "USD", timeframe: .day,
                                tradingPeriod: nil, selectedPoint: .constant(nil)).padding(),
            size: CGSize(width: 402, height: 320))
    }

    @Test func currencyPicker() {
        assertViewSnapshot(of: NavigationStack { CurrencyPickerView(selectedCurrency: .constant("USD")) },
                           named: "usd-selected")
    }

    @Test func addTransactionModes() {
        // Add mode's DatePicker defaults to Date() — render-only.
        ViewRender.assertRenders(
            NavigationStack {
                AddTransactionSheet(symbol: "AAPL", companyName: "Apple", onSave: { _, _, _, _ in })
            })
        let editing = StockTransaction(id: "t-1", type: .buy, shares: 10, totalCost: 1000,
                                       date: Self.fixedDate)
        assertViewSnapshot(
            of: NavigationStack {
                AddTransactionSheet(symbol: "AAPL", companyName: "Apple", currency: "USD",
                                    editingTransaction: editing, onSave: { _, _, _, _ in })
            },
            named: "edit")
    }

    // MARK: - Manager-backed screens

    @Test func stockPortfolioPopulatedAndRepresentativeSet() async throws {
        let manager = try await Self.seededManager()
        withPinnedDefaults(["displayCurrency": "USD"]) {
            let view = NavigationStack {
                StockPortfolioView(portfolioManager: manager, yahooService: Self.stubbedYahoo())
            }
            assertViewSnapshot(of: view, named: "populated")
            assertViewSnapshot(of: view, named: "dark", appearance: .dark)
            assertViewSnapshot(of: view.environment(\.dynamicTypeSize, .accessibility2), named: "a11y-xl")
        }
    }

    @Test func stockDetailWithTransactions() async throws {
        let manager = try await Self.seededManager()
        let holding = Self.holding(transactions: [
            StockTransaction(id: "t-1", type: .buy, shares: 10, totalCost: 1000, date: Self.fixedDate),
            StockTransaction(id: "t-2", type: .sell, shares: 2, totalCost: 300,
                             date: Date(timeIntervalSince1970: 1_705_000_000)),
        ])
        withPinnedDefaults(["displayCurrency": "USD"]) {
            assertViewSnapshot(
                of: NavigationStack {
                    StockDetailView(holding: holding, portfolioManager: manager,
                                    yahooService: Self.stubbedYahoo())
                },
                named: "with-transactions")
        }
    }

    @Test func stockSearchEmpty() async throws {
        let manager = try await Self.seededManager()
        assertViewSnapshot(
            of: NavigationStack {
                StockSearchView(portfolioManager: manager, yahooService: Self.stubbedYahoo())
            },
            named: "empty")
    }

    @Test func stockOnboarding() throws {
        StubURLProtocol.reset()
        let store = try InMemoryLocalStore.make()
        // StockOnboardingView lost its own NavigationStack when Stocks was
        // hoisted to the host — wrapped here to mirror the host stack
        // MainTabView always supplies now (its navigationTitle("Stocks")
        // needs an ancestor stack to render through).
        assertViewSnapshot(
            of: NavigationStack {
                StockOnboardingView(portfolioManager: StockPortfolioManager(store: store),
                                    yahooService: Self.stubbedYahoo())
            },
            named: "empty")
    }

    @Test func stocksViewShellRendersOnly() {
        // StocksView owns a manager over LocalStore.shared (process-global,
        // machine-dependent cache) — render-only.
        ViewRender.assertRenders(StocksView())
    }
}
}
