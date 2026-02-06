//
//  StocksView.swift
//  Groo
//
//  Main entry point for Stock portfolio feature.
//  Shows onboarding if no holdings exist, otherwise shows portfolio.
//

import SwiftUI

struct StocksView: View {
    @State private var portfolioManager = StockPortfolioManager()
    @State private var yahooService = YahooFinanceService()

    var body: some View {
        Group {
            if portfolioManager.hasHoldings {
                StockPortfolioView(
                    portfolioManager: portfolioManager,
                    yahooService: yahooService
                )
            } else {
                StockOnboardingView(
                    portfolioManager: portfolioManager,
                    yahooService: yahooService
                )
            }
        }
        .onAppear {
            portfolioManager.loadCachedHoldings()
        }
        .task {
            if portfolioManager.hasHoldings {
                await portfolioManager.refreshPrices(using: yahooService)
            }
        }
    }
}
