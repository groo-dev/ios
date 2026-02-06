//
//  AddTransactionSheet.swift
//  Groo
//
//  Form for adding or editing a stock transaction (buy/sell).
//

import SwiftUI

struct AddTransactionSheet: View {
    let symbol: String
    let companyName: String
    var currency: String = "USD"
    var editingTransaction: StockTransaction? = nil
    let onSave: (TransactionType, Double, Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var type: TransactionType = .buy
    @State private var sharesText = ""
    @State private var totalCostText = ""
    @State private var date = Date()

    private var isEditing: Bool {
        editingTransaction != nil
    }

    private var isValid: Bool {
        guard let shares = Double(sharesText), shares > 0 else { return false }
        guard let cost = Double(totalCostText), cost > 0 else { return false }
        return true
    }

    private var costPerShare: Double? {
        guard let shares = Double(sharesText), shares > 0,
              let cost = Double(totalCostText) else { return nil }
        return cost / shares
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(symbol)
                            .font(.headline)
                        Text(companyName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Transaction") {
                    Picker("Type", selection: $type) {
                        Text("Buy").tag(TransactionType.buy)
                        Text("Sell").tag(TransactionType.sell)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Shares")
                        Spacer()
                        TextField("0", text: $sharesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text(type == .buy ? "Total Cost" : "Total Received")
                        Spacer()
                        HStack(spacing: 2) {
                            Text(CurrencyFormatter.symbol(for: currency))
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $totalCostText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if let cps = costPerShare {
                    Section("Summary") {
                        HStack {
                            Text("Cost per Share")
                            Spacer()
                            Text(CurrencyFormatter.format(cps, currencyCode: currency))
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let shares = Double(sharesText),
                              let cost = Double(totalCostText) else { return }
                        onSave(type, shares, cost, date)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let tx = editingTransaction {
                    type = tx.type
                    sharesText = formatNumber(tx.shares)
                    totalCostText = formatNumber(tx.totalCost)
                    date = tx.date
                }
            }
        }
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}
