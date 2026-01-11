//
//  PassPlaceholderView.swift
//  Groo
//
//  Placeholder view for Pass feature (coming soon).
//

import SwiftUI

struct PassPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "key.fill")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary.opacity(0.5))

                Text("Pass")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Coming Soon")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Secure password manager with end-to-end encryption")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxl)

                Spacer()
            }
            .navigationTitle("Pass")
        }
    }
}

#Preview {
    PassPlaceholderView()
}
