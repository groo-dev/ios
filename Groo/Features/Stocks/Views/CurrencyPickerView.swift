//
//  CurrencyPickerView.swift
//  Groo
//
//  Currency selection view for display currency preference.
//

import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selectedCurrency: String
    @Environment(\.dismiss) private var dismiss

    private static let currencies: [(code: String, name: String)] = [
        ("AED", "UAE Dirham"),
        ("USD", "US Dollar"),
        ("EUR", "Euro"),
        ("GBP", "British Pound"),
        ("JPY", "Japanese Yen"),
        ("CAD", "Canadian Dollar"),
        ("AUD", "Australian Dollar"),
        ("CHF", "Swiss Franc"),
        ("CNY", "Chinese Yuan"),
        ("HKD", "Hong Kong Dollar"),
        ("SGD", "Singapore Dollar"),
        ("SEK", "Swedish Krona"),
        ("KRW", "South Korean Won"),
        ("INR", "Indian Rupee"),
        ("BRL", "Brazilian Real"),
        ("NZD", "New Zealand Dollar"),
    ]

    var body: some View {
        List {
            ForEach(Self.currencies, id: \.code) { currency in
                Button {
                    selectedCurrency = currency.code
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currency.code)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(currency.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedCurrency == currency.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Brand.primary)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Display Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}
