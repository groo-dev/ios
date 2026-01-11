//
//  UnlockView.swift
//  Groo
//
//  Password entry with Face ID/Touch ID support.
//

import SwiftUI
import LocalAuthentication

struct UnlockView: View {
    @Environment(AuthService.self) private var authService

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
                Image(systemName: "lock.fill")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary)

                Text("Unlock Groo")
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
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    signOut()
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

    private func signOut() {
        try? authService.logout()
        onSignOut()
    }
}

#Preview {
    UnlockView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        onUnlock: {},
        onSignOut: {}
    )
    .environment(AuthService())
}
