//
//  StockSearchView.swift
//  Groo
//
//  Search sheet for finding stocks to add to watchlist.
//

import SwiftUI

struct StockSearchView: View {
    let portfolioManager: StockPortfolioManager
    let yahooService: YahooFinanceService

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [StockSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var existingSymbols: Set<String> {
        Set(portfolioManager.holdings.map(\.symbol))
    }

    private var filteredResults: [StockSearchResult] {
        results.filter { !existingSymbols.contains($0.symbol.uppercased()) }
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if filteredResults.isEmpty && !searchText.isEmpty {
                    Text("No results found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(filteredResults) { result in
                        Button {
                            portfolioManager.addHolding(
                                symbol: result.symbol,
                                companyName: result.name,
                                exchange: result.exchange
                            )
                            Task {
                                await portfolioManager.refreshPrices(using: yahooService)
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                ZStack {
                                    Circle().fill(Theme.Brand.primary.opacity(0.1))
                                    Text(String(result.symbol.prefix(1)))
                                        .font(.headline)
                                        .foregroundStyle(Theme.Brand.primary)
                                }
                                .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.symbol)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(result.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(result.exchange)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(result.type)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search stocks...")
            .navigationTitle("Add Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: searchText) {
                searchTask?.cancel()
                let query = searchText
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    // Debounce
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    isSearching = true
                    defer { isSearching = false }
                    do {
                        let searchResults = try await yahooService.search(query: query)
                        guard !Task.isCancelled else { return }
                        results = searchResults
                    } catch {
                        guard !Task.isCancelled else { return }
                        results = []
                    }
                }
            }
        }
    }
}
