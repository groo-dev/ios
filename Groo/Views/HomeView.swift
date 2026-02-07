//
//  HomeView.swift
//  Groo
//
//  Dashboard with at-a-glance summaries for Stocks, Crypto, and Pad.
//

import SwiftUI

struct HomeView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService

    @AppStorage("selectedTab") private var selectedTab: TabID = .home
    @AppStorage("displayCurrency") private var displayCurrency: String = "USD"

    @State private var stockManager = StockPortfolioManager()
    @State private var yahooService = YahooFinanceService()
    @State private var walletManager: WalletManager?
    @State private var coinGeckoService = CoinGeckoService()
    @State private var ethereumService = EthereumService()

    @State private var stockSparkline: [Double] = []
    @State private var cryptoSparkline: [Double] = []
    @State private var cryptoTrendPositive = true
    @State private var cryptoTotal: Double = 0
    @State private var padItems: [DecryptedListItem] = []
    @State private var toastState = ToastState()
    @State private var isPasting = false
    @State private var scrollOffset: CGFloat = 0

    private var logoScale: CGFloat {
        guard scrollOffset > 0 else { return 1 }
        return 1 + scrollOffset / 150
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    stocksCard
                    cryptoCard
                    padCard
                }
                .padding(Theme.Spacing.lg)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                -geo.contentOffset.y - geo.contentInsets.top
            } action: { _, new in
                scrollOffset = new
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(.grooLogo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .scaleEffect(logoScale, anchor: .top)
                }
            }
        }
        .toast(isPresented: $toastState.isPresented, message: toastState.message, style: toastState.style)
        .onAppear { loadCachedData() }
        .task { await refreshData() }
    }

    // MARK: - Stocks Card

    private var stocksCard: some View {
        Button { selectedTab = .stocks } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                cardHeader(title: "Stocks", icon: TabID.stocks.icon)

                if stockManager.hasHoldings {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(CurrencyFormatter.format(stockManager.totalValue, currencyCode: displayCurrency))
                                .font(.title2.bold())
                                .foregroundStyle(.primary)

                            let gainLoss = stockManager.totalGainLoss
                            let gainLossPercent = stockManager.totalGainLossPercent
                            let isPositive = gainLoss >= 0
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption.bold())
                                Text("\(CurrencyFormatter.format(abs(gainLoss), currencyCode: displayCurrency)) (\(String(format: "%+.2f%%", gainLossPercent)))")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)

                            let dayChange = stockManager.totalDayGainLoss
                            Text("Today: \(CurrencyFormatter.format(dayChange, currencyCode: displayCurrency, showSign: true))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !stockSparkline.isEmpty {
                            SparklineView(
                                data: stockSparkline,
                                color: stockManager.totalDayGainLoss >= 0 ? Theme.Colors.success : Theme.Colors.error
                            )
                            .frame(width: 80, height: 40)
                        }
                    }
                } else {
                    Text("Add your first stock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Crypto Card

    private var cryptoCard: some View {
        Button { selectedTab = .crypto } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                cardHeader(title: "Wallet", icon: TabID.crypto.icon)

                if let walletManager, walletManager.hasWallets {
                    if cryptoTotal > 0 {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(CurrencyFormatter.format(cryptoTotal, currencyCode: "USD"))
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)

                                Text("\(walletManager.walletAddresses.count) wallet\(walletManager.walletAddresses.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !cryptoSparkline.isEmpty {
                                SparklineView(
                                    data: cryptoSparkline,
                                    color: cryptoTrendPositive ? Theme.Colors.success : Theme.Colors.error
                                )
                                .frame(width: 80, height: 40)
                            }
                        }
                    } else {
                        Text("Open wallet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Import a wallet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pad Card

    private var padCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button { selectedTab = .pad } label: {
                cardHeader(title: "Pad", icon: TabID.pad.icon)
            }
            .buttonStyle(.plain)

            if padService.isUnlocked {
                if padItems.isEmpty {
                    Text("No items yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(padItems.prefix(3)) { item in
                            Button {
                                padService.copyToClipboard(item.text)
                                toastState.showCopied()
                            } label: {
                                HStack {
                                    Text(item.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    Task { await pasteFromClipboard() }
                } label: {
                    Label("Paste from Clipboard", systemImage: "clipboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Brand.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Brand.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(isPasting)
            } else {
                Button { selectedTab = .pad } label: {
                    Label("Unlock Pad", systemImage: "lock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func cardHeader(title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }

    private func loadCachedData() {
        stockManager.loadCachedHoldings()

        if walletManager == nil {
            walletManager = WalletManager(passService: passService)
        }

        // Load cached crypto portfolio from SwiftData
        if let address = walletManager?.activeAddress {
            let cached = LocalStore.shared.getCachedPortfolio(wallet: address)
            cryptoTotal = cached.filter { token in
                token.contractAddress == nil ||
                TokenTrackingManager.trackingState(for: token.contractAddress!, wallet: address) == true
            }.reduce(0) { $0 + $1.balance * $1.priceUSD }
        }

        if padService.isUnlocked {
            padItems = (try? padService.getDecryptedItems()) ?? []
        }
    }

    private func refreshData() async {
        // Refresh stock prices
        if stockManager.hasHoldings {
            await stockManager.refreshPrices(using: yahooService)

            // Fetch sparkline for largest holding
            if let topHolding = stockManager.holdings
                .filter({ $0.hasTransactions })
                .max(by: { $0.currentValue < $1.currentValue }) {
                do {
                    let chart = try await yahooService.getChartData(symbol: topHolding.symbol, timeframe: .day)
                    stockSparkline = chart.points.map(\.price)
                } catch {}
            }
        }

        // Refresh crypto: ETH sparkline + live portfolio total
        do {
            let points = try await coinGeckoService.getMarketChart(coinId: "ethereum", days: 1)
            cryptoSparkline = points.map(\.price)
            if let first = points.first, let last = points.last {
                cryptoTrendPositive = last.price >= first.price
            }
        } catch {}

        if let address = walletManager?.activeAddress, walletManager?.hasWallets == true {
            do {
                async let ethBalance = ethereumService.getEthBalance(address: address)
                async let ethPrice = coinGeckoService.getEthPrice()

                let balance = try await ethBalance
                let price = try await ethPrice
                let ethValue = balance * (price.usd ?? 0)

                // Add cached token values (tokens don't change as fast)
                let cached = LocalStore.shared.getCachedPortfolio(wallet: address)
                let tokenValue = cached.filter { $0.contractAddress != nil &&
                    TokenTrackingManager.trackingState(for: $0.contractAddress!, wallet: address) == true
                }.reduce(0) { $0 + $1.balance * $1.priceUSD }

                cryptoTotal = ethValue + tokenValue
            } catch {
                // Keep cached value on failure — already loaded in loadCachedData
            }
        }

        // Refresh pad items
        if padService.isUnlocked {
            padItems = (try? padService.getDecryptedItems()) ?? []
        }
    }

    private func pasteFromClipboard() async {
        isPasting = true
        defer { isPasting = false }

        do {
            guard let item = try await padService.createFromClipboard() else {
                toastState.showError("Clipboard is empty")
                return
            }
            await syncService.addItem(item)
            toastState.show("Item added")
            padItems = (try? padService.getDecryptedItems()) ?? []
        } catch {
            toastState.showError("Failed to create item")
        }
    }
}

// MARK: - Card Style

private extension View {
    func cardStyle() -> some View {
        padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}
