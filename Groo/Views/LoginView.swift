//
//  LoginView.swift
//  Groo
//
//  "Sign in with Groo" — OAuth login via GrooAuth (browser + PKCE).
//  Follows Apple Human Interface Guidelines for authentication screens.
//

import SwiftUI
import UIKit
import AuthenticationServices
import GrooAuth
import os

struct LoginView: View {
    @Environment(AuthService.self) private var authService

    @State private var isLoading = false
    @State private var errorMessage: String?

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

                    // Sign in
                    VStack(spacing: Theme.Spacing.lg) {
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

                        Button {
                            signIn()
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Sign in with Groo")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Brand.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    Spacer(minLength: Theme.Spacing.xxl)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let anchor = resolvePresentationAnchor()
                try await authService.startSignIn(anchor: anchor)
            } catch GrooAuthError.userCancelled {
                // User dismissed the sign-in sheet — just return to the button.
            } catch {
                Log.store.error("Sign in failed: \(String(describing: error), privacy: .public)")
                errorMessage = Self.message(for: error)
            }
            isLoading = false
        }
    }

    /// Resolves the foreground key window to anchor the OAuth web session.
    private func resolvePresentationAnchor() -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first(where: { $0.activationState == .foregroundActive }) ?? windowScenes.first
        if let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first {
            return keyWindow
        }
        // Should be unreachable while the app is on-screen presenting this view,
        // but ASPresentationAnchor is non-optional, so fall back to a fresh window
        // rather than force-unwrapping.
        return UIWindow()
    }

    /// Renders a `GrooAuthError` verbatim (it names the specific failure); falls
    /// back to `String(describing:)` for anything else.
    private static func message(for error: Error) -> String {
        switch error {
        case GrooAuthError.transport(let reason):
            return reason
        case GrooAuthError.protocolError(let protocolError):
            return protocolError.errorDescription ?? protocolError.error
        case GrooAuthError.invalidResponse(let reason):
            return reason
        case GrooAuthError.stateMismatch:
            return "Sign-in response didn't match the request. Please try again."
        case GrooAuthError.idTokenInvalid(let reason):
            return reason
        case GrooAuthError.signedOut:
            return "You've been signed out. Please sign in again."
        case GrooAuthError.userCancelled:
            return ""
        default:
            return String(describing: error)
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
