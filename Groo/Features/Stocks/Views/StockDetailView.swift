//
//  StockDetailView.swift
//  Groo
//
//  Detail view for a stock showing price chart and optional transactions.
//

import SwiftUI

struct StockDetailView: View {
    let holding: StockHolding
    let portfolioManager: StockPortfolioManager
    let yahooService: YahooFinanceService

    @State private var selectedTimeframe: StockChartTimeframe = .day
    @State private var chartPoints: [StockPricePoint] = []
    @State private var tradingPeriod: TradingPeriod?
    @State private var loadedCharts: [StockChartTimeframe: StockChartData] = [:]
    @State private var isLoadingChart = false
    @State private var chartError: String?
    @State private var showAddTransaction = false
    @State private var editingTransaction: StockTransaction?
    @State private var scrubbedPoint: StockPricePoint?
    @Environment(\.dismiss) private var dismiss

    private var displayPrice: Double {
        scrubbedPoint?.price ?? currentHolding.currentPrice
    }

    private var displayChange: Double {
        if let scrubbed = scrubbedPoint,
           let first = chartPoints.first?.price, first > 0 {
            return ((scrubbed.price - first) / first) * 100
        }
        if let first = chartPoints.first?.price, first > 0,
           let last = chartPoints.last?.price {
            return ((last - first) / first) * 100
        }
        return holding.changePercent
    }

    private var currentHolding: StockHolding {
        portfolioManager.holdings.first { $0.symbol == holding.symbol } ?? holding
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Price header
                VStack(spacing: Theme.Spacing.xs) {
                    Text(currentHolding.companyName)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if displayPrice > 0 {
                        Text(CurrencyFormatter.format(displayPrice, currencyCode: currentHolding.currency))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())

                        HStack(spacing: 4) {
                            Image(systemName: displayChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            Text(formatPercent(displayChange))
                                .contentTransition(.numericText())
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(displayChange >= 0 ? .green : .red)
                        .animation(.default, value: displayChange)
                    } else {
                        Text("--")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, Theme.Spacing.md)

                // Price chart
                StockPriceChartView(
                    data: chartPoints,
                    isLoading: isLoadingChart,
                    isPositive: displayChange >= 0,
                    errorMessage: chartError,
                    currencyCode: currentHolding.currency,
                    timeframe: selectedTimeframe,
                    tradingPeriod: selectedTimeframe == .day ? tradingPeriod : nil,
                    selectedPoint: $scrubbedPoint
                )
                .frame(height: 200)
                .padding(.horizontal)

                // Timeframe picker
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(StockChartTimeframe.allCases, id: \.self) { tf in
                        Text(tf.rawValue).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Divider()

                // Holdings summary (only when transactions exist)
                if currentHolding.hasTransactions {
                    VStack(spacing: Theme.Spacing.sm) {
                        summaryRow("Net Shares", value: formatShares(currentHolding.netShares))
                        summaryRow("Avg Cost", value: currentHolding.netShares > 0
                            ? CurrencyFormatter.format(currentHolding.totalInvested / currentHolding.netShares, currencyCode: currentHolding.currency) : "--")
                        summaryRow("Total Invested", value: CurrencyFormatter.format(currentHolding.totalInvested, currencyCode: currentHolding.currency))
                        summaryRow("Market Value", value: currentHolding.currentPrice > 0
                            ? CurrencyFormatter.format(currentHolding.currentValue, currencyCode: currentHolding.currency) : "--")

                        if currentHolding.currentPrice > 0,
                           let gainLoss = currentHolding.totalGainLoss,
                           let gainLossPct = currentHolding.totalGainLossPercent {
                            Divider()
                            HStack {
                                Text("Total Return")
                                    .font(.subheadline)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CurrencyFormatter.format(gainLoss, currencyCode: currentHolding.currency, showSign: true))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(String(format: "%+.2f%%", gainLossPct))
                                        .font(.caption)
                                }
                                .foregroundStyle(gainLoss >= 0 ? .green : .red)
                            }

                            if let dayGL = currentHolding.dayGainLoss, dayGL != 0 {
                                HStack {
                                    Text("Today")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(CurrencyFormatter.format(dayGL, currencyCode: currentHolding.currency, showSign: true))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(dayGL >= 0 ? .green : .red)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .padding(.horizontal)
                }

                // Transactions section
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Transactions")
                            .font(.headline)
                        Spacer()
                        Button {
                            showAddTransaction = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.Brand.primary)
                        }
                    }
                    .padding(.horizontal)

                    if currentHolding.transactions.isEmpty {
                        Text("Add a purchase to track your gains")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.lg)
                    } else {
                        ForEach(currentHolding.transactions.sorted(by: { $0.date > $1.date })) { tx in
                            transactionRow(tx)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingTransaction = tx
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        portfolioManager.deleteTransaction(id: tx.id)
                                    } label: {
                                        Label("Delete Transaction", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .navigationTitle(currentHolding.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionSheet(
                symbol: currentHolding.symbol,
                companyName: currentHolding.companyName,
                currency: currentHolding.currency
            ) { type, shares, totalCost, date in
                portfolioManager.addTransaction(
                    to: currentHolding.symbol,
                    type: type,
                    shares: shares,
                    totalCost: totalCost,
                    date: date
                )
            }
        }
        .sheet(item: $editingTransaction) { tx in
            AddTransactionSheet(
                symbol: currentHolding.symbol,
                companyName: currentHolding.companyName,
                currency: currentHolding.currency,
                editingTransaction: tx
            ) { type, shares, totalCost, date in
                portfolioManager.updateTransaction(
                    id: tx.id,
                    type: type,
                    shares: shares,
                    totalCost: totalCost,
                    date: date
                )
            }
        }
        .task {
            await loadChart()
        }
        .onChange(of: selectedTimeframe) {
            Task { await loadChart() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func transactionRow(_ tx: StockTransaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(tx.type == .buy ? "Buy" : "Sell")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(tx.type == .buy ? .green : .red)
                    Text("\(formatShares(tx.shares)) shares")
                        .font(.subheadline)
                }
                Text(tx.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.format(tx.totalCost, currencyCode: currentHolding.currency))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("@ \(CurrencyFormatter.format(tx.costPerShare, currencyCode: currentHolding.currency))/share")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Data Loading

    private func loadChart() async {
        if let cached = loadedCharts[selectedTimeframe] {
            chartPoints = cached.points
            tradingPeriod = cached.tradingPeriod
            return
        }

        isLoadingChart = true
        chartError = nil
        defer { isLoadingChart = false }

        do {
            let result = try await yahooService.getChartData(
                symbol: holding.symbol,
                timeframe: selectedTimeframe
            )
            loadedCharts[selectedTimeframe] = result
            chartPoints = result.points
            tradingPeriod = result.tradingPeriod
        } catch {
            chartPoints = []
            tradingPeriod = nil
            chartError = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func formatPercent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }

    private func formatShares(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
