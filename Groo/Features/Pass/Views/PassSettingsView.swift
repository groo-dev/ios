//
//  PassSettingsView.swift
//  Groo
//
//  Pass-specific settings including biometric authentication options.
//

import LocalAuthentication
import SwiftUI

struct PassSettingsView: View {
    let passService: PassService
    let onDismiss: () -> Void

    @State private var biometricEnabled: Bool = false
    @State private var biometricType: LABiometryType = .none
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Biometric Section
                Section {
                    Toggle(isOn: $biometricEnabled) {
                        Label {
                            Text(biometricLabel)
                        } icon: {
                            Image(systemName: biometricIcon)
                                .foregroundStyle(.blue)
                        }
                    }
                    .onChange(of: biometricEnabled) { _, newValue in
                        Task {
                            await toggleBiometric(enabled: newValue)
                        }
                    }
                    .disabled(biometricType == .none || isLoading)
                } header: {
                    Text("Authentication")
                } footer: {
                    if biometricType == .none {
                        Text("Biometric authentication is not available on this device.")
                    } else {
                        Text("Use \(biometricLabel) to quickly unlock your vault instead of entering your master password.")
                    }
                }

                // Security Info Section
                Section {
                    HStack {
                        Label("Encryption", systemImage: "lock.shield.fill")
                        Spacer()
                        Text("AES-256-GCM")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Key Derivation", systemImage: "key.fill")
                        Spacer()
                        Text("PBKDF2")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Iterations", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text("600,000")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Your vault is encrypted locally before being synced to the server.")
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        passService.lock()
                        onDismiss()
                    } label: {
                        Label("Lock Vault Now", systemImage: "lock.fill")
                    }
                } header: {
                    Text("Actions")
                }
            }
            .navigationTitle("Pass Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
        .task {
            await loadBiometricState()
        }
    }

    // MARK: - Biometric Helpers

    private var biometricLabel: String {
        switch biometricType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Biometric"
        }
    }

    private var biometricIcon: String {
        switch biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    private func loadBiometricState() async {
        // Check biometric availability
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }

        // Check if biometric key exists
        biometricEnabled = passService.canUnlockWithBiometric
    }

    private func toggleBiometric(enabled: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            if enabled {
                // Enable biometric - this requires the user to have unlocked with password first
                // The key should already be stored if they've unlocked
                if !passService.canUnlockWithBiometric {
                    // Need to store the key with biometric protection
                    // This is typically done during password unlock
                    errorMessage = "Please unlock with your master password first to enable biometric."
                    biometricEnabled = false
                }
            } else {
                // Disable biometric - remove the stored key
                try passService.disableBiometric()
                biometricEnabled = false
            }
        } catch {
            errorMessage = error.localizedDescription
            // Revert toggle state
            biometricEnabled = !enabled
        }
    }
}
