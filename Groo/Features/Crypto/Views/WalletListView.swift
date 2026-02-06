//
//  WalletListView.swift
//  Groo
//
//  Manage wallets: view all, switch active, rename, delete.
//

import SwiftUI

struct WalletListView: View {
    let walletManager: WalletManager
    let passService: PassService

    @Environment(\.dismiss) private var dismiss

    @State private var walletItems: [PassCryptoWalletItem] = []
    @State private var showAddWallet = false
    @State private var showDeleteConfirm = false
    @State private var walletToDelete: PassCryptoWalletItem?
    @State private var editingWallet: PassCryptoWalletItem?
    @State private var editName = ""
    @State private var showUnlockPrompt = false
    @State private var error: String?

    var body: some View {
        List {
            if !passService.isUnlocked {
                Section {
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("Unlock Pass to manage wallets")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Unlock") {
                            Task { try? await passService.unlockWithBiometric() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section {
                if walletItems.isEmpty && passService.isUnlocked {
                    Text("No wallets found in vault")
                        .foregroundStyle(.secondary)
                } else if walletItems.isEmpty {
                    // Show cached addresses (no vault details)
                    ForEach(walletManager.walletAddresses, id: \.self) { address in
                        walletRow(address: address, name: nil, isActive: address.lowercased() == walletManager.activeAddress?.lowercased())
                    }
                } else {
                    ForEach(walletItems, id: \.id) { wallet in
                        walletRow(address: wallet.address, name: wallet.name, isActive: wallet.address.lowercased() == walletManager.activeAddress?.lowercased())
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    walletToDelete = wallet
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    editingWallet = wallet
                                    editName = wallet.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                    }
                }
            } header: {
                Text("Wallets (\(walletManager.walletAddresses.count))")
            } footer: {
                Text("Tap a wallet to make it active. The active wallet is used for portfolio and transactions.")
            }
        }
        .navigationTitle("Manage Wallets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddWallet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddWallet) {
            WalletOnboardingView(
                walletManager: walletManager,
                passService: passService
            )
        }
        .alert("Delete Wallet", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {
                walletToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let wallet = walletToDelete {
                    Task {
                        do {
                            try await walletManager.deleteWallet(address: wallet.address)
                            loadWallets()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    walletToDelete = nil
                }
            }
        } message: {
            if let wallet = walletToDelete {
                Text("Remove \"\(wallet.name)\" (\(wallet.address.prefix(6))...\(wallet.address.suffix(4)))? This will delete the wallet and its keys from the vault.")
            }
        }
        .alert("Rename Wallet", isPresented: .init(
            get: { editingWallet != nil },
            set: { if !$0 { editingWallet = nil } }
        )) {
            TextField("Wallet name", text: $editName)
            Button("Cancel", role: .cancel) { editingWallet = nil }
            Button("Save") {
                if let wallet = editingWallet, !editName.isEmpty {
                    Task {
                        try? await walletManager.renameWallet(address: wallet.address, newName: editName)
                        loadWallets()
                    }
                }
                editingWallet = nil
            }
        } message: {
            Text("Enter a new name for this wallet.")
        }
        .alert("Error", isPresented: .init(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .onAppear { loadWallets() }
        .onChange(of: passService.isUnlocked) { loadWallets() }
        .onChange(of: walletManager.walletAddresses) { loadWallets() }
    }

    // MARK: - Wallet Row

    private func walletRow(address: String, name: String?, isActive: Bool) -> some View {
        Button {
            walletManager.setActiveAddress(address)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isActive ? Theme.Brand.primary : Color(.secondarySystemBackground))
                    Image(systemName: "wallet.bifold")
                        .font(.subheadline)
                        .foregroundStyle(isActive ? .white : .secondary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "Wallet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("\(address.prefix(6))...\(address.suffix(4))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Brand.primary)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func loadWallets() {
        if passService.isUnlocked {
            walletItems = walletManager.getWalletItems()
        } else {
            walletItems = []
        }
    }
}
