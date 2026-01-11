//
//  PadSettingsView.swift
//  Groo
//
//  Pad-specific settings with lock and sign out options.
//

import SwiftUI

struct PadSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let onLock: () -> Void
    let onSignOut: () -> Void

    @State private var showLockConfirm = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showLockConfirm = true
                    } label: {
                        Label("Lock Pad", systemImage: "lock")
                    }
                }

                Section {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Lock Pad?", isPresented: $showLockConfirm) {
                Button("Lock") {
                    dismiss()
                    onLock()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your password to access Pad again.")
            }
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    onSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your PAT token again to sign back in.")
            }
        }
    }
}

#Preview {
    PadSettingsView(
        onLock: {},
        onSignOut: {}
    )
}
