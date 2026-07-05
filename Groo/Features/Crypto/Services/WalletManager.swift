//
//  WalletManager.swift
//  Groo
//
//  Manages crypto wallet creation, import, and key access.
//  Wallet addresses cached in @AppStorage for portfolio loading without Pass unlock.
//  Private keys stored securely in Pass vault.
//

import BigInt
import CryptoSwift
import Foundation
import os
import SwiftUI
import Web3Core
import web3swift

@MainActor
@Observable
class WalletManager {
    private let passService: PassService
    private let defaults: UserDefaults

    private(set) var walletAddresses: [String] = []
    private(set) var isLoading = false
    private(set) var error: String?

    /// The currently active wallet address used for portfolio and transactions.
    private(set) var activeAddress: String?

    init(passService: PassService, defaults: UserDefaults = .standard) {
        self.passService = passService
        self.defaults = defaults
        loadCachedAddresses()
        resolveActiveAddress()
    }

    func setActiveAddress(_ address: String) {
        activeAddress = address
        defaults.set(address, forKey: "activeWalletAddress")
    }

    private func resolveActiveAddress() {
        if let saved = defaults.string(forKey: "activeWalletAddress"),
           !saved.isEmpty {
            activeAddress = saved
        } else {
            activeAddress = walletAddresses.first
        }
    }

    var hasWallets: Bool {
        !walletAddresses.isEmpty
    }

    /// True from wallet creation until the recovery-phrase reveal sheet is
    /// dismissed. CryptoView keeps the onboarding view (which presents that
    /// sheet) on screen while this is set — without it, the walletAddresses
    /// append inside createWallet() flips hasWallets, CryptoView swaps to
    /// PortfolioView, and the sheet is torn down before the mnemonic is ever
    /// shown to the user.
    private(set) var pendingRecoveryPhraseReveal = false

    /// Called when the recovery-phrase reveal sheet closes (confirm, cancel,
    /// or swipe-down) — lets CryptoView advance to the portfolio.
    func completeRecoveryPhraseReveal() {
        pendingRecoveryPhraseReveal = false
    }

    /// Get wallet info (name + address) for all wallets. Requires Pass vault unlocked.
    func getWalletItems() -> [PassCryptoWalletItem] {
        let items = passService.getItems(type: .cryptoWallet)
        return items.compactMap { item in
            if case .cryptoWallet(let wallet) = item { return wallet }
            return nil
        }
    }

    /// Rename a wallet
    func renameWallet(address: String, newName: String) async throws {
        let items = passService.getItems(type: .cryptoWallet)
        for item in items {
            if case .cryptoWallet(var wallet) = item,
               wallet.address.lowercased() == address.lowercased() {
                wallet.name = newName
                wallet.updatedAt = Int(Date().timeIntervalSince1970 * 1000)
                try await passService.updateItem(.cryptoWallet(wallet))
                return
            }
        }
        Log.wallet.error("renameWallet: no vault item found for address \(address, privacy: .public)")
        throw WalletError.walletNotFound
    }

    // MARK: - Address Cache

    private func loadCachedAddresses() {
        let raw = defaults.string(forKey: "walletAddresses") ?? ""
        walletAddresses = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private func saveCachedAddresses() {
        defaults.set(walletAddresses.joined(separator: ","), forKey: "walletAddresses")
        resolveActiveAddress()
    }

    // MARK: - Create Wallet

    /// Create a new wallet with a BIP39 mnemonic
    func createWallet() async throws -> (mnemonic: String, address: String) {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let generatedMnemonics: String?
        do {
            generatedMnemonics = try BIP39.generateMnemonics(bitsOfEntropy: 128)
        } catch {
            Log.wallet.error("BIP39 mnemonic generation failed: \(String(describing: error))")
            throw WalletError.mnemonicGenerationFailed
        }
        guard let mnemonics = generatedMnemonics else {
            Log.wallet.error("BIP39 mnemonic generation returned nil")
            throw WalletError.mnemonicGenerationFailed
        }

        let createdKeystore: BIP32Keystore?
        do {
            createdKeystore = try BIP32Keystore(mnemonics: mnemonics, password: "")
        } catch {
            Log.wallet.error("BIP32 keystore creation failed: \(String(describing: error))")
            throw WalletError.keystoreCreationFailed
        }
        guard let keystore = createdKeystore else {
            Log.wallet.error("BIP32 keystore creation returned nil")
            throw WalletError.keystoreCreationFailed
        }

        guard let address = keystore.addresses?.first else {
            throw WalletError.addressDerivationFailed
        }

        let addressString = address.address

        // Get private key for storage
        let privateKeyData = try keystore.UNSAFE_getPrivateKeyData(
            password: "",
            account: address
        )
        let privateKeyHex = privateKeyData.toHexString()

        // Store in Pass vault
        let walletItem = PassCryptoWalletItem.create(
            name: "Ethereum Wallet",
            address: addressString,
            seedPhrase: mnemonics,
            privateKey: privateKeyHex,
            publicKey: address.address
        )

        try await passService.addItem(.cryptoWallet(walletItem))

        // Hold CryptoView on the onboarding flow until the recovery phrase
        // has been shown — set before the walletAddresses append flips
        // hasWallets.
        pendingRecoveryPhraseReveal = true

        // Cache address
        if !walletAddresses.contains(addressString) {
            walletAddresses.append(addressString)
            saveCachedAddresses()
        }

        return (mnemonics, addressString)
    }

    // MARK: - Import Wallet

    /// Import wallet from seed phrase
    func importWallet(seedPhrase: String) async throws -> String {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let trimmed = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let importedKeystore: BIP32Keystore?
        do {
            importedKeystore = try BIP32Keystore(mnemonics: trimmed, password: "")
        } catch {
            Log.wallet.error("BIP32 keystore creation from seed phrase failed: \(String(describing: error))")
            throw WalletError.invalidSeedPhrase
        }
        guard let keystore = importedKeystore else {
            Log.wallet.error("BIP32 keystore creation from seed phrase returned nil")
            throw WalletError.invalidSeedPhrase
        }

        guard let address = keystore.addresses?.first else {
            throw WalletError.addressDerivationFailed
        }

        let addressString = address.address

        let privateKeyData = try keystore.UNSAFE_getPrivateKeyData(
            password: "",
            account: address
        )
        let privateKeyHex = privateKeyData.toHexString()

        let walletItem = PassCryptoWalletItem.create(
            name: "Imported Wallet",
            address: addressString,
            seedPhrase: trimmed,
            privateKey: privateKeyHex,
            publicKey: address.address
        )

        try await passService.addItem(.cryptoWallet(walletItem))

        if !walletAddresses.contains(addressString) {
            walletAddresses.append(addressString)
            saveCachedAddresses()
        }

        return addressString
    }

    /// Import wallet from private key
    func importWallet(privateKey: String) async throws -> String {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let cleanKey = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey

        guard let keyData = Data.fromHex(cleanKey) else {
            throw WalletError.invalidPrivateKey
        }

        let importedKeystore: EthereumKeystoreV3?
        do {
            importedKeystore = try EthereumKeystoreV3(privateKey: keyData, password: "")
        } catch {
            Log.wallet.error("Keystore creation from private key failed: \(String(describing: error))")
            throw WalletError.invalidPrivateKey
        }
        guard let keystore = importedKeystore else {
            Log.wallet.error("Keystore creation from private key returned nil")
            throw WalletError.invalidPrivateKey
        }

        guard let address = keystore.addresses?.first else {
            throw WalletError.addressDerivationFailed
        }

        let addressString = address.address

        let walletItem = PassCryptoWalletItem.create(
            name: "Imported Wallet",
            address: addressString,
            privateKey: cleanKey,
            publicKey: address.address
        )

        try await passService.addItem(.cryptoWallet(walletItem))

        if !walletAddresses.contains(addressString) {
            walletAddresses.append(addressString)
            saveCachedAddresses()
        }

        return addressString
    }

    // MARK: - Key Access

    /// Get private key for a wallet address (requires Pass vault to be unlocked)
    func getPrivateKey(for address: String) -> String? {
        let items = passService.getItems(type: .cryptoWallet)
        for item in items {
            if case .cryptoWallet(let wallet) = item,
               wallet.address.lowercased() == address.lowercased() {
                return wallet.privateKey
            }
        }
        return nil
    }

    /// Sign a transaction (requires Pass vault to be unlocked)
    func signTransaction(
        to: String,
        value: BigUInt,
        data: Data = Data(),
        nonce: BigUInt,
        gasPrice: BigUInt,
        gasLimit: BigUInt,
        chainId: BigUInt = 1,
        fromAddress: String
    ) throws -> Data {
        guard let privateKeyHex = getPrivateKey(for: fromAddress),
              let privateKeyData = Data.fromHex(privateKeyHex) else {
            throw WalletError.privateKeyNotFound
        }

        guard let toAddress = EthereumAddress(to) else {
            Log.wallet.error("Invalid recipient address: \(to, privacy: .public)")
            throw WalletError.invalidRecipient
        }

        var transaction = CodableTransaction(
            to: toAddress,
            nonce: nonce,
            chainID: chainId,
            value: value,
            data: data,
            gasLimit: gasLimit,
            gasPrice: gasPrice
        )

        try transaction.sign(privateKey: privateKeyData)

        guard let encoded = transaction.encode() else {
            throw WalletError.transactionSigningFailed
        }

        return encoded
    }

    // MARK: - Delete Wallet

    func deleteWallet(address: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let items = passService.getItems(type: .cryptoWallet)
        for item in items {
            if case .cryptoWallet(let wallet) = item,
               wallet.address.lowercased() == address.lowercased() {
                try await passService.deleteItem(item)
                break
            }
        }

        walletAddresses.removeAll { $0.lowercased() == address.lowercased() }
        saveCachedAddresses()

        if activeAddress?.lowercased() == address.lowercased() {
            setActiveAddress(walletAddresses.first ?? "")
        }
    }
}

// MARK: - Errors

enum WalletError: Error, LocalizedError {
    case mnemonicGenerationFailed
    case keystoreCreationFailed
    case addressDerivationFailed
    case invalidSeedPhrase
    case invalidPrivateKey
    case invalidRecipient
    case privateKeyNotFound
    case transactionSigningFailed
    case walletNotFound

    var errorDescription: String? {
        switch self {
        case .mnemonicGenerationFailed: "Failed to generate mnemonic"
        case .keystoreCreationFailed: "Failed to create keystore"
        case .addressDerivationFailed: "Failed to derive address"
        case .invalidSeedPhrase: "Invalid seed phrase"
        case .invalidPrivateKey: "Invalid private key"
        case .invalidRecipient: "Invalid recipient address"
        case .privateKeyNotFound: "Private key not found in vault"
        case .transactionSigningFailed: "Failed to sign transaction"
        case .walletNotFound: "Wallet not found in vault"
        }
    }
}
