//
//  CryptoPlaceholderView.swift
//  Groo
//
//  Placeholder view for Crypto feature (coming soon).
//

import SwiftUI

struct CryptoPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary.opacity(0.5))

                Text("Crypto")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Coming Soon")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Cryptocurrency portfolio tracking")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxl)

                Spacer()
            }
            .navigationTitle("Crypto")
        }
    }
}

#Preview {
    CryptoPlaceholderView()
}
