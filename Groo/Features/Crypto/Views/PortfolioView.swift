//
//  PortfolioView.swift
//  Groo
//
//  Portfolio view showing wallet assets with live prices.
//

import SwiftUI

struct PortfolioView: View {
    let walletManager: WalletManager
    let ethereumService: EthereumService
    let coinGeckoService: CoinGeckoService
    let passService: PassService

    @State private var assets: [CryptoAsset] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedAsset: CryptoAsset?
    @State private var showAddWallet = false
    @State private var showReceive = false
    @State private var showWalletList = false
    @State private var otherTokensExpanded = false

    private var trackedAssets: [CryptoAsset] {
        guard let wallet = walletManager.activeAddress else { return assets }
        return assets.filter { asset in
            asset.contractAddress == nil || // ETH always tracked
            TokenTrackingManager.trackingState(for: asset.contractAddress!, wallet: wallet) == true
        }
    }

    private var otherAssets: [CryptoAsset] {
        guard let wallet = walletManager.activeAddress else { return [] }
        return assets.filter { asset in
            guard let contract = asset.contractAddress else { return false }
            return TokenTrackingManager.trackingState(for: contract, wallet: wallet) == false
        }
    }

    private var totalValue: Double {
        trackedAssets.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        NavigationStack {
            List {
                // Portfolio header
                Section {
                    VStack(spacing: Theme.Spacing.xs) {
                        if let address = walletManager.activeAddress {
                            Button {
                                showWalletList = true
                            } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text("\(address.prefix(6))...\(address.suffix(4))")
                                        .font(.caption.monospaced())
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }

                        Text(formatCurrency(totalValue))
                            .font(.system(size: 34, weight: .bold, design: .rounded))

                        Text("Total Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .listRowBackground(Color.clear)
                }

                // Tracked assets
                Section("Assets") {
                    if isLoading && assets.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                    } else if trackedAssets.isEmpty {
                        Text("No assets found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(trackedAssets) { asset in
                            Button {
                                selectedAsset = asset
                            } label: {
                                assetRow(asset)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                if asset.contractAddress != nil {
                                    Button {
                                        untrackAsset(asset)
                                    } label: {
                                        Label("Untrack", systemImage: "eye.slash")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }

                // Other (untracked) tokens
                if !otherAssets.isEmpty {
                    Section {
                        DisclosureGroup(
                            "Other Tokens (\(otherAssets.count))",
                            isExpanded: $otherTokensExpanded
                        ) {
                            ForEach(otherAssets) { asset in
                                Button {
                                    selectedAsset = asset
                                } label: {
                                    assetRow(asset)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        trackAsset(asset)
                                    } label: {
                                        Label("Track", systemImage: "eye")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wallet")
            .refreshable {
                await loadPortfolio()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showWalletList = true
                    } label: {
                        Image(systemName: "wallet.bifold")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showReceive = true
                    } label: {
                        Image(systemName: "qrcode")
                    }
                    Button {
                        showAddWallet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedAsset) { asset in
                NavigationStack {
                    AssetDetailView(
                        asset: asset,
                        walletManager: walletManager,
                        ethereumService: ethereumService,
                        coinGeckoService: coinGeckoService,
                        passService: passService
                    )
                }
            }
            .sheet(isPresented: $showAddWallet) {
                WalletOnboardingView(
                    walletManager: walletManager,
                    passService: passService
                )
            }
            .sheet(isPresented: $showWalletList) {
                NavigationStack {
                    WalletListView(
                        walletManager: walletManager,
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
                await loadPortfolio()
            }
            .onChange(of: walletManager.activeAddress) {
                Task { await loadPortfolio() }
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Asset Row

    @ViewBuilder
    private func assetRow(_ asset: CryptoAsset) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Token icon
            if let iconURL = asset.iconURL {
                AsyncImage(url: iconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Circle().fill(Color(.secondarySystemBackground))
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(Theme.Brand.primary.opacity(0.1))
                    Text(String(asset.symbol.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(Theme.Brand.primary)
                }
                .frame(width: 36, height: 36)
            }

            // Name and balance
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(formatBalance(asset.balance)) \(asset.symbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Value and change
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(asset.value))
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 2) {
                    Image(systemName: asset.priceChange24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(formatPercent(asset.priceChange24h))
                        .font(.caption)
                }
                .foregroundStyle(asset.priceChange24h >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Data Loading

    private func loadPortfolio() async {
        isLoading = true
        defer { isLoading = false }

        guard let address = walletManager.activeAddress else { return }

        var loadedAssets: [CryptoAsset] = []

        do {
            // Load ETH balance, ETH price, and token balances concurrently
            async let ethBalanceTask = ethereumService.getEthBalance(address: address)
            async let ethPriceTask = coinGeckoService.getEthPrice()
            async let tokenBalancesTask = ethereumService.getTokenBalances(address: address)

            let ethBalance = try await ethBalanceTask
            let ethPrice = try await ethPriceTask
            let tokenBalances = try await tokenBalancesTask

            // Add ETH asset
            loadedAssets.append(CryptoAsset(
                id: "eth",
                symbol: "ETH",
                name: "Ethereum",
                balance: ethBalance,
                price: ethPrice.usd ?? 0,
                priceChange24h: ethPrice.usd_24h_change ?? 0,
                iconURL: nil,
                decimals: 18,
                contractAddress: nil
            ))

            // Blockscout returns metadata with each token — no extra calls needed
            for token in tokenBalances {
                let decimals = Int(token.decimals) ?? 18
                let rawBalance = Double(token.balance) ?? 0
                let balance = rawBalance / pow(10, Double(decimals))

                guard balance > 0 else { continue }

                loadedAssets.append(CryptoAsset(
                    id: token.contractAddress,
                    symbol: token.symbol,
                    name: token.name,
                    balance: balance,
                    price: 0,
                    priceChange24h: 0,
                    iconURL: nil,
                    decimals: decimals,
                    contractAddress: token.contractAddress
                ))
            }

            // Partition token contracts by tracking state
            var trackedContracts: [String] = []
            var unknownContracts: [String] = []

            for asset in loadedAssets {
                guard let contract = asset.contractAddress else { continue }
                let state = TokenTrackingManager.trackingState(for: contract, wallet: address)
                switch state {
                case .some(true): trackedContracts.append(contract)
                case .some(false): break // untracked — skip price fetch
                case .none: unknownContracts.append(contract) // needs detection
                }
            }

            // Fetch prices for tracked + unknown tokens
            let contractsToPrice = trackedContracts + unknownContracts
            var allPrices: [String: CoinGeckoSimplePrice] = [:]
            if !contractsToPrice.isEmpty {
                if let prices = try? await coinGeckoService.getTokenPrices(contracts: contractsToPrice) {
                    allPrices = prices
                }
            }

            // Auto-classify unknown tokens based on CoinGecko recognition
            for contract in unknownContracts {
                let recognized = allPrices[contract.lowercased()] != nil
                TokenTrackingManager.setTrackingState(recognized, for: contract, wallet: address)
            }

            // Apply prices to assets
            loadedAssets = loadedAssets.map { asset in
                guard let contract = asset.contractAddress,
                      let price = allPrices[contract.lowercased()] else {
                    return asset
                }
                return CryptoAsset(
                    id: asset.id,
                    symbol: asset.symbol,
                    name: asset.name,
                    balance: asset.balance,
                    price: price.usd ?? 0,
                    priceChange24h: price.usd_24h_change ?? 0,
                    iconURL: asset.iconURL,
                    decimals: asset.decimals,
                    contractAddress: asset.contractAddress
                )
            }

            // Sort by value (highest first)
            assets = loadedAssets.sorted { $0.value > $1.value }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func trackAsset(_ asset: CryptoAsset) {
        guard let contract = asset.contractAddress,
              let wallet = walletManager.activeAddress else { return }
        TokenTrackingManager.setTrackingState(true, for: contract, wallet: wallet)
        // Fetch price for newly tracked token
        Task {
            if let prices = try? await coinGeckoService.getTokenPrices(contracts: [contract]),
               let price = prices[contract.lowercased()] {
                if let idx = assets.firstIndex(where: { $0.id == asset.id }) {
                    assets[idx] = CryptoAsset(
                        id: asset.id,
                        symbol: asset.symbol,
                        name: asset.name,
                        balance: asset.balance,
                        price: price.usd ?? 0,
                        priceChange24h: price.usd_24h_change ?? 0,
                        iconURL: asset.iconURL,
                        decimals: asset.decimals,
                        contractAddress: asset.contractAddress
                    )
                }
            }
        }
    }

    private func untrackAsset(_ asset: CryptoAsset) {
        guard let contract = asset.contractAddress,
              let wallet = walletManager.activeAddress else { return }
        TokenTrackingManager.setTrackingState(false, for: contract, wallet: wallet)
    }

    // MARK: - Formatting

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatBalance(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value < 0.0001 { return "<0.0001" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", abs(value))
    }
}
