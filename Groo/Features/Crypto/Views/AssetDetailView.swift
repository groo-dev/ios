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
    @State private var isLoadingChart = false
    @State private var chartError: String?
    @State private var showSend = false
    @State private var showReceive = false
    @State private var livePrice: CoinGeckoSimplePrice?
    @Environment(\.dismiss) private var dismiss

    private var displayPrice: Double {
        livePrice?.usd ?? asset.price
    }

    private var displayChange: Double {
        livePrice?.usd_24h_change ?? asset.priceChange24h
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

                    Text(formatCurrency(displayPrice))
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    HStack(spacing: 4) {
                        Image(systemName: displayChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(formatPercent(displayChange))
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(displayChange >= 0 ? .green : .red)
                }
                .padding(.top, Theme.Spacing.md)

                // Price chart
                PriceChartView(
                    data: chartData,
                    isLoading: isLoadingChart,
                    isPositive: displayChange >= 0,
                    errorMessage: chartError
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

                    Text(formatCurrency(displayValue))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            await fetchPriceIfNeeded()
        }
        .onChange(of: selectedTimeframe) {
            Task { await loadChart() }
        }
    }

    // MARK: - Data Loading

    private func fetchPriceIfNeeded() async {
        guard asset.price == 0, let contract = asset.contractAddress else { return }
        if let prices = try? await coinGeckoService.getTokenPrices(contracts: [contract]),
           let price = prices[contract.lowercased()] {
            livePrice = price
        }
    }

    private func loadChart() async {
        isLoadingChart = true
        chartError = nil
        defer { isLoadingChart = false }

        do {
            if let contract = asset.contractAddress {
                chartData = try await coinGeckoService.getContractMarketChart(
                    contractAddress: contract,
                    days: selectedTimeframe.days
                )
            } else {
                chartData = try await coinGeckoService.getMarketChart(
                    coinId: "ethereum",
                    days: selectedTimeframe.days
                )
            }
        } catch {
            chartData = []
            chartError = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
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
