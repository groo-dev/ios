//
//  LoginView.swift
//  Groo
//
//  PAT token entry for authentication.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService

    @State private var patToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                // Logo
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary)

                Text("Groo")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign in with your Personal Access Token")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                // Token input
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Personal Access Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("groo_pat_...", text: $patToken)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Sign in button
                Button {
                    signIn()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Brand.primary)
                .disabled(patToken.isEmpty || isLoading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                // Get token link
                Button("Get a token from Accounts") {
                    authService.openAccountSettings()
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        do {
            try authService.login(patToken: patToken)
        } catch {
            errorMessage = "Invalid token. Please try again."
        }

        isLoading = false
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
