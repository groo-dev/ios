//
//  GlobalLockView.swift
//  Groo
//
//  Global lock screen that unlocks all features with a single biometric prompt.
//  Appears before MainTabView when biometric keys exist in keychain.
//

import SwiftUI
import LocalAuthentication

struct GlobalLockView: View {
    let padService: PadService
    let passService: PassService
    let onUnlock: () -> Void
    let onSignOut: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirm = false
    @State private var biometricType: LABiometryType = .none

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.2)

                // Lock icon and title
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.Brand.primary)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: isLoading)

                    Text("Groo is Locked")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Unlock with \(biometricName) to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, Theme.Spacing.xxl)

                // Unlock button
                VStack(spacing: Theme.Spacing.lg) {
                    Button {
                        unlockAll()
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: biometricIconName)
                                    .font(.title2)
                                Text("Unlock with \(biometricName)")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Brand.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    .disabled(isLoading)

                    // Skip option
                    Button {
                        onUnlock()
                    } label: {
                        Text("Use Password Instead")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .disabled(isLoading)

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                        }
                        .font(.footnote)
                        .foregroundStyle(.red)
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
            // Auto-trigger biometric on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                unlockAll()
            }
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

    private func unlockAll() {
        isLoading = true
        errorMessage = nil

        Task {
            var anyUnlocked = false

            // Try to unlock Pad with biometric (single biometric session)
            if padService.canUnlockWithBiometric && !padService.isUnlocked {
                do {
                    let success = try padService.unlockWithBiometric()
                    if success {
                        anyUnlocked = true
                    }
                } catch {
                    // Biometric cancelled or failed for Pad
                }
            }

            // Try to unlock Pass with biometric (same biometric session if available)
            if passService.canUnlockWithBiometric && !passService.isUnlocked {
                do {
                    let success = try await passService.unlockWithBiometric()
                    if success {
                        anyUnlocked = true
                    }
                } catch {
                    // Biometric cancelled or failed for Pass
                }
            }

            isLoading = false

            // If any service was unlocked, or if user cancelled, proceed
            // The individual feature unlock views will handle remaining unlocks
            if anyUnlocked {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onUnlock()
        }
    }
}

#Preview {
    GlobalLockView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        passService: PassService(),
        onUnlock: {},
        onSignOut: {}
    )
}
