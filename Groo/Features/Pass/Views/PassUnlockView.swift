//
//  PassUnlockView.swift
//  Groo
//
//  Pass unlock view with biometric and master password support.
//

import SwiftUI
import LocalAuthentication

struct PassUnlockView: View {
    let passService: PassService
    let onUnlock: () -> Void
    let onSignOut: () -> Void

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirm = false
    @State private var biometricType: LABiometryType = .none
    @State private var showPasswordField = false
    @FocusState private var isPasswordFocused: Bool

    private var canUseBiometric: Bool {
        passService.canUnlockWithBiometric && biometricType != .none
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: geometry.size.height * 0.12)

                    // Lock icon and title
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.Brand.primary)
                            .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: isLoading)

                        Text("Pass is Locked")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Enter your master password to unlock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, Theme.Spacing.xxl)

                    // Unlock options
                    VStack(spacing: Theme.Spacing.lg) {
                        // Biometric button (primary action)
                        if canUseBiometric {
                            Button {
                                unlockWithBiometric()
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: biometricIconName)
                                        .font(.title2)
                                    Text("Unlock with \(biometricName)")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Brand.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                            .disabled(isLoading)
                        }

                        // Password section
                        if showPasswordField || !canUseBiometric {
                            passwordSection
                        } else {
                            // Show password option
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showPasswordField = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isPasswordFocused = true
                                }
                            } label: {
                                Text("Use Master Password")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    Spacer(minLength: Theme.Spacing.xxl)

                    // Sign out option
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirm = true
                    }
                    .font(.footnote)
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                onSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to enter your PAT token again to sign back in.")
        }
        .onAppear {
            checkBiometricAvailability()
            // Auto-trigger biometric if available
            if canUseBiometric {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    unlockWithBiometric()
                }
            } else {
                showPasswordField = true
                isPasswordFocused = true
            }
        }
    }

    private var passwordSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if canUseBiometric {
                HStack {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                }
                .padding(.vertical, Theme.Spacing.sm)
            }

            // Password input
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Master Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                SecureField("Enter master password", text: $password)
                    .font(.body)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .textContentType(.password)
                    .focused($isPasswordFocused)
                    .onSubmit {
                        unlockWithPassword()
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

            // Unlock button
            Button {
                unlockWithPassword()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Unlock")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Brand.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .disabled(password.isEmpty || isLoading)
        }
    }

    private var biometricIconName: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock"
        }
    }

    private var biometricName: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometric"
        }
    }

    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        }
    }

    private func unlockWithBiometric() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let success = try await passService.unlockWithBiometric()
                if success {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onUnlock()
                } else {
                    withAnimation {
                        showPasswordField = true
                    }
                    errorMessage = "Biometric unlock failed. Try your master password."
                    isPasswordFocused = true
                }
            } catch {
                // Biometric cancelled or failed, show password field
                withAnimation {
                    showPasswordField = true
                }
            }
            isLoading = false
        }
    }

    private func unlockWithPassword() {
        guard !password.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        isPasswordFocused = false

        Task {
            do {
                let success = try await passService.unlock(password: password)
                if success {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onUnlock()
                } else {
                    errorMessage = "Incorrect master password"
                    isPasswordFocused = true
                }
            } catch {
                errorMessage = error.localizedDescription
                isPasswordFocused = true
            }
            isLoading = false
        }
    }
}

#Preview {
    PassUnlockView(
        passService: PassService(),
        onUnlock: {},
        onSignOut: {}
    )
}
