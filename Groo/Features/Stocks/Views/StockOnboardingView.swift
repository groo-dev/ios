//
//  StockOnboardingView.swift
//  Groo
//
//  Empty state view prompting user to add their first stock.
//

import SwiftUI

struct StockOnboardingView: View {
    let portfolioManager: StockPortfolioManager
    let yahooService: YahooFinanceService

    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary.opacity(0.7))

                Text("Stock Portfolio")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Track stocks, view price charts, and monitor your portfolio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxl)

                Spacer()

                Button {
                    showSearch = true
                } label: {
                    Label("Add Your First Stock", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Brand.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .navigationTitle("Stocks")
            .sheet(isPresented: $showSearch) {
                StockSearchView(
                    portfolioManager: portfolioManager,
                    yahooService: yahooService
                )
            }
        }
    }
}
