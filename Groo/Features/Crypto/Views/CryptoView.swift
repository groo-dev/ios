//
//  CryptoView.swift
//  Groo
//
//  Main entry point for Crypto wallet feature.
//  Shows onboarding if no wallets exist, otherwise shows portfolio.
//

import SwiftUI

struct CryptoView: View {
    let passService: PassService

    @State private var walletManager: WalletManager?
    @State private var ethereumService = EthereumService()
    @State private var coinGeckoService = CoinGeckoService()

    var body: some View {
        Group {
            if let walletManager {
                if walletManager.hasWallets {
                    PortfolioView(
                        walletManager: walletManager,
                        ethereumService: ethereumService,
                        coinGeckoService: coinGeckoService,
                        passService: passService
                    )
                } else {
                    WalletOnboardingView(
                        walletManager: walletManager,
                        passService: passService
                    )
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if walletManager == nil {
                walletManager = WalletManager(passService: passService)
            }
        }
    }
}
