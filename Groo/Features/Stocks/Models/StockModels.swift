//
//  StockModels.swift
//  Groo
//
//  Data models for Stock portfolio feature.
//

import Foundation

// MARK: - View Models

enum TransactionType: String, Hashable, Sendable {
    case buy, sell
}

struct StockTransaction: Identifiable, Hashable {
    let id: String
    let type: TransactionType
    let shares: Double
    let totalCost: Double
    let date: Date

    var costPerShare: Double {
        shares > 0 ? totalCost / shares : 0
    }
}

struct StockHolding: Identifiable, Hashable {
    let symbol: String
    let companyName: String
    let exchange: String
    let currency: String
    var currentPrice: Double
    var changePercent: Double
    var previousClose: Double
    var transactions: [StockTransaction]

    var id: String { symbol }

    var hasTransactions: Bool { !transactions.isEmpty }

    // Net shares = sum(buy shares) - sum(sell shares)
    var netShares: Double {
        let bought = transactions.filter { $0.type == .buy }.reduce(0) { $0 + $1.shares }
        let sold = transactions.filter { $0.type == .sell }.reduce(0) { $0 + $1.shares }
        return bought - sold
    }

    // Total invested = sum(buy costs) - sum(sell proceeds)
    var totalInvested: Double {
        let buyCost = transactions.filter { $0.type == .buy }.reduce(0) { $0 + $1.totalCost }
        let sellProceeds = transactions.filter { $0.type == .sell }.reduce(0) { $0 + $1.totalCost }
        return buyCost - sellProceeds
    }

    // Current value (only meaningful with transactions)
    var currentValue: Double {
        netShares * currentPrice
    }

    var totalGainLoss: Double? {
        guard hasTransactions else { return nil }
        return currentValue - totalInvested
    }

    var totalGainLossPercent: Double? {
        guard hasTransactions, totalInvested > 0 else { return nil }
        return ((currentValue - totalInvested) / totalInvested) * 100
    }

    var dayGainLoss: Double? {
        guard hasTransactions, previousClose > 0 else { return nil }
        return netShares * (currentPrice - previousClose)
    }
}

struct StockQuote: Sendable {
    let symbol: String
    let price: Double
    let previousClose: Double
    let changePercent: Double
    let exchange: String
    let currency: String
}

struct StockSearchResult: Identifiable, Hashable, Sendable {
    let symbol: String
    let name: String
    let exchange: String
    let type: String

    var id: String { symbol }
}

struct StockPricePoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let price: Double
}

struct TradingPeriod: Sendable {
    let open: Date
    let close: Date
}

struct StockChartData: Sendable {
    let points: [StockPricePoint]
    let tradingPeriod: TradingPeriod?
}

enum StockChartTimeframe: String, CaseIterable, Sendable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case sixMonth = "6M"
    case year = "1Y"

    var range: String {
        switch self {
        case .day: "1d"
        case .week: "5d"
        case .month: "1mo"
        case .sixMonth: "6mo"
        case .year: "1y"
        }
    }

    var interval: String {
        switch self {
        case .day: "5m"
        case .week: "15m"
        case .month: "1d"
        case .sixMonth: "1d"
        case .year: "1wk"
        }
    }
}

// MARK: - Yahoo Finance Response Types

nonisolated struct YahooChartResponse: Codable, Sendable {
    let chart: YahooChartResult
}

nonisolated struct YahooChartResult: Codable, Sendable {
    let result: [YahooChartData]?
    let error: YahooChartError?
}

nonisolated struct YahooChartError: Codable, Sendable {
    let code: String?
    let description: String?
}

nonisolated struct YahooChartData: Codable, Sendable {
    let meta: YahooChartMeta
    let timestamp: [Int]?
    let indicators: YahooChartIndicators
}

nonisolated struct YahooChartMeta: Codable, Sendable {
    let regularMarketPrice: Double?
    let previousClose: Double?
    let exchangeName: String?
    let symbol: String?
    let currency: String?
    let currentTradingPeriod: YahooTradingPeriods?
}

nonisolated struct YahooTradingPeriods: Codable, Sendable {
    let pre: YahooTradingPeriodDetail?
    let regular: YahooTradingPeriodDetail?
    let post: YahooTradingPeriodDetail?
}

nonisolated struct YahooTradingPeriodDetail: Codable, Sendable {
    let start: Int?
    let end: Int?
    let gmtoffset: Int?
}

nonisolated struct YahooChartIndicators: Codable, Sendable {
    let quote: [YahooChartQuote]
}

nonisolated struct YahooChartQuote: Codable, Sendable {
    let close: [Double?]?
    let open: [Double?]?
    let high: [Double?]?
    let low: [Double?]?
    let volume: [Int?]?
}

nonisolated struct YahooSearchResponse: Codable, Sendable {
    let quotes: [YahooSearchQuote]
}

nonisolated struct YahooSearchQuote: Codable, Sendable {
    let symbol: String?
    let shortname: String?
    let longname: String?
    let exchDisp: String?
    let quoteType: String?
}

// MARK: - Exchange Rate

struct ExchangeRate: Sendable {
    let from: String
    let to: String
    let rate: Double
}

// MARK: - Currency Formatter

enum CurrencyFormatter {
    static func format(_ value: Double, currencyCode: String, showSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        if currencyCode == "INR" {
            formatter.locale = Locale(identifier: "en_IN")
        }
        if currencyCode == "JPY" || currencyCode == "KRW" {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = abs(value) < 1 ? 4 : 2
        }
        let result = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return showSign && value >= 0 ? "+\(result)" : result
    }

    static func symbol(for currencyCode: String) -> String {
        let id = Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: currencyCode])
        return Locale(identifier: id).currencySymbol ?? currencyCode
    }
}

// MARK: - Collection Safe Subscript

nonisolated extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
