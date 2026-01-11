//
//  DrivePlaceholderView.swift
//  Groo
//
//  Placeholder view for Drive feature (coming soon).
//

import SwiftUI

struct DrivePlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "folder.fill")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary.opacity(0.5))

                Text("Drive")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Coming Soon")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Cloud file storage with end-to-end encryption")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxl)

                Spacer()
            }
            .navigationTitle("Drive")
        }
    }
}

#Preview {
    DrivePlaceholderView()
}
