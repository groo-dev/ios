//
//  AssetDetailView.swift
//  Groo
//
//  Detail view for a crypto asset showing price chart, balance, and actions.
//

import SwiftUI

struct AssetDetailView: View {
    let asset: CryptoAsset
    let walletManager: WalletManager
    let ethereumService: EthereumService
    let coinGeckoService: CoinGeckoService
    let passService: PassService

    @State private var selectedTimeframe: ChartTimeframe = .day
    @State private var chartData: [PricePoint] = []
    @State private var loadedCharts: [ChartTimeframe: [PricePoint]] = [:]
    @State private var isLoadingChart = false
    @State private var chartError: String?
    @State private var showSend = false
    @State private var showReceive = false
    @State private var scrubbedPoint: PricePoint?
    @Environment(\.dismiss) private var dismiss

    private var displayPrice: Double {
        scrubbedPoint?.price ?? asset.price
    }

    private var displayChange: Double {
        if let scrubbed = scrubbedPoint,
           let first = chartData.first?.price, first > 0 {
            return ((scrubbed.price - first) / first) * 100
        }
        if let first = chartData.first?.price, first > 0,
           let last = chartData.last?.price {
            return ((last - first) / first) * 100
        }
        return asset.priceChange24h
    }

    private var displayValue: Double {
        asset.balance * displayPrice
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Price header
                VStack(spacing: Theme.Spacing.xs) {
                    Text(asset.name)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if displayPrice > 0 {
                        Text(formatCurrency(displayPrice))
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
                        Text("—")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, Theme.Spacing.md)

                // Price chart
                PriceChartView(
                    data: chartData,
                    isLoading: isLoadingChart,
                    isPositive: displayChange >= 0,
                    errorMessage: chartError,
                    selectedPoint: $scrubbedPoint
                )
                .frame(height: 200)
                .padding(.horizontal)

                // Timeframe picker
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(ChartTimeframe.allCases, id: \.self) { tf in
                        Text(tf.rawValue).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Divider()

                // Balance
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Your Balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(formatBalance(asset.balance)) \(asset.symbol)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(displayPrice > 0 ? formatCurrency(displayValue) : "—")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding()

                // Action buttons
                HStack(spacing: Theme.Spacing.lg) {
                    Button {
                        showSend = true
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                            Text("Send")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }

                    Button {
                        showReceive = true
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title)
                            Text("Receive")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                }
                .foregroundStyle(Theme.Brand.primary)
                .padding(.horizontal)
            }
        }
        .navigationTitle(asset.symbol)
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
        .sheet(isPresented: $showSend) {
            NavigationStack {
                SendView(
                    asset: asset,
                    walletManager: walletManager,
                    ethereumService: ethereumService,
                    passService: passService
                )
            }
        }
        .sheet(isPresented: $showReceive) {
            if let address = walletManager.activeAddress {
                NavigationStack {
                    ReceiveView(address: address)
                }
            }
        }
        .task {
            await loadChart()
        }
        .onChange(of: selectedTimeframe) {
            Task { await loadChart() }
        }
    }

    // MARK: - Data Loading

    private func loadChart() async {
        // Use locally cached chart data if available
        if let cached = loadedCharts[selectedTimeframe] {
            chartData = cached
            return
        }

        isLoadingChart = true
        chartError = nil
        defer { isLoadingChart = false }

        do {
            var points: [PricePoint]
            if let contract = asset.contractAddress {
                points = try await coinGeckoService.getContractMarketChart(
                    contractAddress: contract,
                    days: selectedTimeframe.days
                )
            } else {
                points = try await coinGeckoService.getMarketChart(
                    coinId: "ethereum",
                    days: selectedTimeframe.days
                )
            }

            if selectedTimeframe == .hour {
                let cutoff = Date().addingTimeInterval(-3600)
                points = points.filter { $0.timestamp >= cutoff }
            }

            loadedCharts[selectedTimeframe] = points
            chartData = points
        } catch {
            chartData = []
            chartError = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value < 1 ? 4 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatBalance(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value < 0.0001 { return "<0.0001" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }
}
