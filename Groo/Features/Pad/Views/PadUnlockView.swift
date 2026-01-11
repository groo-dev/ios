//
//  PadUnlockView.swift
//  Groo
//
//  Pad-specific unlock view with password entry.
//

import SwiftUI

struct PadUnlockView: View {
    let padService: PadService
    let syncService: SyncService
    let onUnlock: () -> Void
    let onSignOut: () -> Void

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                // Lock icon
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary)

                Text("Unlock Pad")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enter your encryption password")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Password input
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Password")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit {
                            unlock()
                        }
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Unlock button
                Button {
                    unlock()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Brand.primary)
                .disabled(password.isEmpty || isLoading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                // Sign out button
                Button("Sign Out", role: .destructive) {
                    showSignOutConfirm = true
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
            .navigationTitle("Pad")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    onSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your PAT token again to sign back in.")
            }
        }
    }

    private func unlock() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let success = try await padService.unlock(password: password)
                if success {
                    onUnlock()
                } else {
                    errorMessage = "Incorrect password"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    PadUnlockView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        onUnlock: {},
        onSignOut: {}
    )
}
