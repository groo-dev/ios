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
import SwiftUI
import Web3Core
import web3swift

@MainActor
@Observable
class WalletManager {
    private let passService: PassService

    private(set) var walletAddresses: [String] = []
    private(set) var isLoading = false
    private(set) var error: String?

    /// The currently active wallet address used for portfolio and transactions.
    private(set) var activeAddress: String?

    init(passService: PassService) {
        self.passService = passService
        loadCachedAddresses()
        resolveActiveAddress()
    }

    func setActiveAddress(_ address: String) {
        activeAddress = address
        UserDefaults.standard.set(address, forKey: "activeWalletAddress")
    }

    private func resolveActiveAddress() {
        let saved = UserDefaults.standard.string(forKey: "activeWalletAddress") ?? ""
        if !saved.isEmpty && walletAddresses.contains(where: { $0.lowercased() == saved.lowercased() }) {
            activeAddress = saved
        } else {
            activeAddress = walletAddresses.first
        }
    }

    var hasWallets: Bool {
        !walletAddresses.isEmpty
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
                break
            }
        }
    }

    // MARK: - Address Cache

    private func loadCachedAddresses() {
        let raw = UserDefaults.standard.string(forKey: "walletAddresses") ?? ""
        walletAddresses = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private func saveCachedAddresses() {
        UserDefaults.standard.set(walletAddresses.joined(separator: ","), forKey: "walletAddresses")
        resolveActiveAddress()
    }

    // MARK: - Create Wallet

    /// Create a new wallet with a BIP39 mnemonic
    func createWallet() async throws -> (mnemonic: String, address: String) {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let mnemonics = try? BIP39.generateMnemonics(bitsOfEntropy: 128) else {
            throw WalletError.mnemonicGenerationFailed
        }

        guard let keystore = try? BIP32Keystore(mnemonics: mnemonics, password: "") else {
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

        guard let keystore = try? BIP32Keystore(mnemonics: trimmed, password: "") else {
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

        guard let keystore = try? EthereumKeystoreV3(privateKey: keyData, password: "") else {
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

        var transaction = CodableTransaction(
            to: EthereumAddress(to)!,
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
    }
}

// MARK: - Errors

enum WalletError: Error, LocalizedError {
    case mnemonicGenerationFailed
    case keystoreCreationFailed
    case addressDerivationFailed
    case invalidSeedPhrase
    case invalidPrivateKey
    case privateKeyNotFound
    case transactionSigningFailed

    var errorDescription: String? {
        switch self {
        case .mnemonicGenerationFailed: "Failed to generate mnemonic"
        case .keystoreCreationFailed: "Failed to create keystore"
        case .addressDerivationFailed: "Failed to derive address"
        case .invalidSeedPhrase: "Invalid seed phrase"
        case .invalidPrivateKey: "Invalid private key"
        case .privateKeyNotFound: "Private key not found in vault"
        case .transactionSigningFailed: "Failed to sign transaction"
        }
    }
}
