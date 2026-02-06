//
//  SettingsView.swift
//  Groo
//
//  App settings and sign out.
//

import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService

    let padService: PadService
    let passService: PassService
    let onSignOut: () -> Void
    let onLock: () -> Void

    @AppStorage("displayCurrency") private var displayCurrency: String = "USD"
    @State private var showSignOutConfirm = false
    @State private var biometricEnabled: Bool = false
    @State private var biometricType: LABiometryType = .none
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
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
                    Text("Use \(biometricLabel) to quickly unlock Pad and Pass instead of entering your password.")
                }
            }

            Section {
                NavigationLink {
                    CustomizeTabsView()
                } label: {
                    Label("Customize Tabs", systemImage: "slider.horizontal.3")
                }
            }

            Section {
                NavigationLink {
                    CurrencyPickerView(selectedCurrency: $displayCurrency)
                } label: {
                    HStack {
                        Label("Display Currency", systemImage: "dollarsign.circle")
                        Spacer()
                        Text(displayCurrency)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    onLock()
                } label: {
                    Label("Lock", systemImage: "lock")
                }

                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersion)
                LabeledContent("Build", value: Bundle.main.buildNumber)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                try? authService.logout()
                onSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to enter your PAT token again to sign back in.")
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

        // Check if biometric key exists for either service
        biometricEnabled = padService.canUnlockWithBiometric || passService.canUnlockWithBiometric
    }

    private func toggleBiometric(enabled: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            if enabled {
                // Enable biometric - requires unlocking with password first
                let padHasBiometric = padService.canUnlockWithBiometric
                let passHasBiometric = passService.canUnlockWithBiometric

                if !padHasBiometric && !passHasBiometric {
                    errorMessage = "Please unlock Pad or Pass with your password first to enable biometric."
                    biometricEnabled = false
                }
            } else {
                // Disable biometric - remove stored keys from both services
                try padService.disableBiometric()
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

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    NavigationStack {
        SettingsView(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            passService: PassService(),
            onSignOut: {},
            onLock: {}
        )
    }
    .environment(AuthService())
}
