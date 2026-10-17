//
//  ReauthBanner.swift
//  Groo
//
//  Shown when the session lapsed but the identity was kept.
//

import SwiftUI

/// Tells someone their session expired without taking the app away from them.
///
/// The wording matters more than it looks. "Signed out" reads as *your things
/// are gone*, which is false — everything on this device is still here and
/// still readable. What stopped is syncing. The banner says that, and stays out
/// of the way until they choose to act.
struct ReauthBanner: View {
    let email: String?
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync paused")
                    .font(.footnote.weight(.semibold))
                Text(email.map { "Sign in again as \($0) to resume" }
                    ?? "Sign in again to resume syncing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Theme.Spacing.xs)

            Button("Sign In", action: onSignIn)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            email.map { "Sync paused. Sign in again as \($0) to resume." }
                ?? "Sync paused. Sign in again to resume syncing."
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        ReauthBanner(email: "someone@groo.dev", onSignIn: {})
        ReauthBanner(email: nil, onSignIn: {})
        Spacer()
    }
}
