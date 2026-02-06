//
//  StockPortfolioView.swift
//  Groo
//
//  Main portfolio list showing stocks, prices, and optional gain/loss.
//

import SwiftUI

struct StockPortfolioView: View {
    let portfolioManager: StockPortfolioManager
    let yahooService: YahooFinanceService

    @AppStorage("displayCurrency") private var displayCurrency: String = "USD"
    @State private var showSearch = false
    @State private var selectedHolding: StockHolding?
    @State private var showStaleReason = false
    @State private var showCurrencyPicker = false

    var body: some View {
        NavigationStack {
            List {
                // Portfolio header
                Section {
                    VStack(spacing: Theme.Spacing.xs) {
                        if portfolioManager.hasAnyTransactions {
                            Text(CurrencyFormatter.format(portfolioManager.totalValue, currencyCode: displayCurrency))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())

                            Button {
                                showCurrencyPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Portfolio Value")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(displayCurrency)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                }
                            }
                            .buttonStyle(.plain)

                            // Gain/loss summary
                            if portfolioManager.totalCostBasis > 0 {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: portfolioManager.totalGainLoss >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption2)
                                    Text("\(CurrencyFormatter.format(abs(portfolioManager.totalGainLoss), currencyCode: displayCurrency)) (\(formatPercent(portfolioManager.totalGainLossPercent)))")
                                        .font(.caption)
                                }
                                .foregroundStyle(portfolioManager.totalGainLoss >= 0 ? .green : .red)
                            }

                            // Day gain/loss
                            if portfolioManager.totalDayGainLoss != 0 {
                                Text("Today: \(CurrencyFormatter.format(portfolioManager.totalDayGainLoss, currencyCode: displayCurrency, showSign: true))")
                                    .font(.caption2)
                                    .foregroundStyle(portfolioManager.totalDayGainLoss >= 0 ? .green : .red)
                            }
                        } else {
                            Text("Watchlist")
                                .font(.system(size: 28, weight: .bold, design: .rounded))

                            Text("\(portfolioManager.holdings.count) stocks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Status indicators
                        if portfolioManager.isRefreshing {
                            HStack(spacing: Theme.Spacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Updating prices...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .transition(.opacity)
                        } else if portfolioManager.isOffline {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "wifi.slash")
                                    .font(.caption2)
                                Text("You're offline")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                            .transition(.opacity)
                        } else if portfolioManager.staleReason != nil {
                            Button {
                                showStaleReason = true
                            } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                    Text("Prices may be outdated")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.orange)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .listRowBackground(Color.clear)
                    .animation(.default, value: portfolioManager.isRefreshing)
                    .animation(.default, value: portfolioManager.isOffline)
                    .animation(.default, value: portfolioManager.staleReason)
                }

                // Holdings
                Section("Stocks") {
                    ForEach(portfolioManager.holdings) { holding in
                        Button {
                            selectedHolding = holding
                        } label: {
                            holdingRow(holding)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                portfolioManager.deleteHolding(symbol: holding.symbol)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stocks")
            .refreshable {
                await portfolioManager.refreshPrices(using: yahooService)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                StockSearchView(
                    portfolioManager: portfolioManager,
                    yahooService: yahooService
                )
            }
            .sheet(item: $selectedHolding) { holding in
                NavigationStack {
                    StockDetailView(
                        holding: holding,
                        portfolioManager: portfolioManager,
                        yahooService: yahooService
                    )
                }
            }
            .alert("Prices may be outdated", isPresented: $showStaleReason) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(portfolioManager.staleReason ?? "")
            }
            .onChange(of: displayCurrency) {
                portfolioManager.displayCurrency = displayCurrency
                Task { await portfolioManager.refreshExchangeRates(using: yahooService) }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    CurrencyPickerView(selectedCurrency: $displayCurrency)
                }
            }
        }
    }

    // MARK: - Holding Row

    @ViewBuilder
    private func holdingRow(_ holding: StockHolding) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Symbol icon
            ZStack {
                Circle().fill(Theme.Brand.primary.opacity(0.1))
                Text(String(holding.symbol.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(Theme.Brand.primary)
            }
            .frame(width: 36, height: 36)

            // Name and optional shares
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if holding.hasTransactions {
                    Text("\(formatShares(holding.netShares)) shares")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(holding.companyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Price and value/change
            VStack(alignment: .trailing, spacing: 2) {
                if holding.currentPrice > 0 {
                    if holding.hasTransactions {
                        let convertedValue = portfolioManager.converted(holding.currentValue, from: holding.currency)
                        Text(CurrencyFormatter.format(convertedValue, currencyCode: displayCurrency))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .contentTransition(.numericText())

                        // Show native currency value if different from display
                        if holding.currency.uppercased() != displayCurrency.uppercased() {
                            Text(CurrencyFormatter.format(holding.currentValue, currencyCode: holding.currency))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let pct = holding.totalGainLossPercent {
                            HStack(spacing: 2) {
                                Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text(formatPercent(pct))
                                    .font(.caption)
                            }
                            .foregroundStyle(pct >= 0 ? .green : .red)
                        }
                    } else {
                        Text(CurrencyFormatter.format(holding.currentPrice, currencyCode: holding.currency))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .contentTransition(.numericText())

                        HStack(spacing: 2) {
                            Image(systemName: holding.changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text(formatPercent(holding.changePercent))
                                .font(.caption)
                        }
                        .foregroundStyle(holding.changePercent >= 0 ? .green : .red)
                    }
                } else {
                    Text("--")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Formatting

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", abs(value))
    }

    private func formatShares(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
