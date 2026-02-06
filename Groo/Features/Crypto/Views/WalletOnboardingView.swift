//
//  WalletOnboardingView.swift
//  Groo
//
//  Onboarding flow for creating or importing a wallet.
//

import SwiftUI

struct WalletOnboardingView: View {
    let walletManager: WalletManager
    let passService: PassService

    @State private var showCreateFlow = false
    @State private var showImportFlow = false
    @State private var generatedMnemonic: String?
    @State private var generatedAddress: String?
    @State private var importText = ""
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showMnemonicConfirm = false
    @State private var showUnlockPrompt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "wallet.bifold")
                    .font(.system(size: Theme.Size.iconHero))
                    .foregroundStyle(Theme.Brand.primary.opacity(0.7))

                Text("Ethereum Wallet")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Create a new wallet or import an existing one")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxl)

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        if passService.isUnlocked {
                            showCreateFlow = true
                        } else {
                            showUnlockPrompt = true
                        }
                    } label: {
                        Label("Create New Wallet", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Brand.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }

                    Button {
                        if passService.isUnlocked {
                            showImportFlow = true
                        } else {
                            showUnlockPrompt = true
                        }
                    } label: {
                        Label("Import Wallet", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(Theme.Brand.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .navigationTitle("Wallet")
            .alert("Unlock Pass", isPresented: $showUnlockPrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Unlock") {
                    Task {
                        try? await passService.unlockWithBiometric()
                    }
                }
            } message: {
                Text("Pass vault must be unlocked to create or import wallets.")
            }
            .sheet(isPresented: $showCreateFlow) {
                createWalletSheet
            }
            .sheet(isPresented: $showImportFlow) {
                importWalletSheet
            }
        }
    }

    // MARK: - Create Wallet Sheet

    private var createWalletSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                if let mnemonic = generatedMnemonic {
                    // Show mnemonic for backup
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Recovery Phrase")
                            .font(.headline)

                        Text("Write down these words in order. You'll need them to recover your wallet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let words = mnemonic.split(separator: " ")
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: Theme.Spacing.sm) {
                            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16, alignment: .trailing)
                                    Text(String(word))
                                        .font(.subheadline.monospaced())
                                }
                                .padding(.vertical, Theme.Spacing.xs)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                        }

                        if let address = generatedAddress {
                            Divider()
                            Text("Address")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(address)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .padding()

                    Spacer()

                    Button {
                        showCreateFlow = false
                        generatedMnemonic = nil
                        generatedAddress = nil
                    } label: {
                        Text("I've Saved My Recovery Phrase")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Brand.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .padding()
                } else {
                    Spacer()
                    if isProcessing {
                        ProgressView("Creating wallet...")
                    }
                    Spacer()
                }
            }
            .navigationTitle("Create Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCreateFlow = false
                        generatedMnemonic = nil
                    }
                }
            }
            .task {
                await createWallet()
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil; showCreateFlow = false }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Import Wallet Sheet

    private var importWalletSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Text("Enter your seed phrase or private key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top)

                TextEditor(text: $importText)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .padding(Theme.Spacing.sm)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .padding(.horizontal)

                if isProcessing {
                    ProgressView("Importing wallet...")
                }

                Spacer()

                Button {
                    Task { await importWallet() }
                } label: {
                    Text("Import")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(importText.isEmpty ? Color.gray : Theme.Brand.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .disabled(importText.isEmpty || isProcessing)
                .padding()
            }
            .navigationTitle("Import Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showImportFlow = false
                        importText = ""
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Actions

    private func createWallet() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let result = try await walletManager.createWallet()
            generatedMnemonic = result.mnemonic
            generatedAddress = result.address
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importWallet() async {
        isProcessing = true
        defer { isProcessing = false }

        let text = importText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            // Detect if it's a private key (hex string) or seed phrase (words)
            if text.hasPrefix("0x") || (text.count == 64 && text.allSatisfy({ $0.isHexDigit })) {
                _ = try await walletManager.importWallet(privateKey: text)
            } else {
                _ = try await walletManager.importWallet(seedPhrase: text)
            }
            showImportFlow = false
            importText = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
