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
                // pendingRecoveryPhraseReveal keeps the onboarding view (and
                // its recovery-phrase sheet) alive after createWallet() flips
                // hasWallets — swapping to the portfolio here would tear the
                // sheet down before the mnemonic is shown.
                if walletManager.hasWallets && !walletManager.pendingRecoveryPhraseReveal {
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
