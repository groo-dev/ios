//
//  PassSettingsView.swift
//  Groo
//
//  Pass-specific settings including security info.
//

import SwiftUI

struct PassSettingsView: View {
    let passService: PassService
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
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

                // Actions
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
        }
    }
}
