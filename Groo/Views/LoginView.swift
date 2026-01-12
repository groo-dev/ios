//
//  LoginView.swift
//  Groo
//
//  PAT token entry for authentication.
//  Follows Apple Human Interface Guidelines for authentication screens.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var authService

    @State private var patToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isTokenFieldFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: geometry.size.height * 0.15)

                    // App branding
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.Brand.primary)
                            .symbolRenderingMode(.hierarchical)

                        Text("Groo")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Secure notes, passwords & files")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, Theme.Spacing.xxl)

                    // Sign in form
                    VStack(spacing: Theme.Spacing.lg) {
                        // Token input
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Personal Access Token")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            SecureField("groo_pat_...", text: $patToken)
                                .font(.body)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($isTokenFieldFocused)
                                .onSubmit {
                                    signIn()
                                }
                        }

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(error)
                            }
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Sign in button
                        Button {
                            signIn()
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Sign In")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Brand.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .disabled(patToken.isEmpty || isLoading)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    Spacer(minLength: Theme.Spacing.xxl)

                    // Footer
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Don't have a token?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            authService.openAccountSettings()
                        } label: {
                            Text("Get one from Groo Accounts")
                                .font(.footnote)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            isTokenFieldFocused = true
        }
    }

    private func signIn() {
        guard !patToken.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        isTokenFieldFocused = false

        Task {
            do {
                try authService.login(patToken: patToken)
            } catch {
                errorMessage = "Invalid token. Please check and try again."
                isTokenFieldFocused = true
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
