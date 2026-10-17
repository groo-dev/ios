//
//  WalletManager.swift
//  Groo
//
//  Manages crypto wallet creation, import, and key access.
//  Wallet addresses cached in @AppStorage for portfolio loading without Pass unlock.
//  Private keys stored securely in Pass vault.
//

import BigInt
import Foundation
import os
import SwiftUI
import WalletCore
// The generated signing-input types (EthereumSigningInput and friends) are
// SwiftProtobuf messages, and their `.with { }` builders resolve only when the
// defining module is imported directly. WalletCore's own tests get away with
// importing just WalletCore because they predate MemberImportVisibility.
import WalletCoreSwiftProtobuf

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

        // 128 bits of entropy is a 12-word BIP39 phrase. Empty passphrase
        // keeps the seed derivation standard (BIP39 salt "mnemonic" + ""),
        // which is what every other wallet assumes when importing this phrase.
        guard let wallet = HDWallet(strength: 128, passphrase: "") else {
            Log.wallet.error("BIP39 mnemonic generation returned nil")
            throw WalletError.mnemonicGenerationFailed
        }
        let mnemonics = wallet.mnemonic

        guard let addressString = wallet.getAddressForCoin(coin: .ethereum),
              let derivedKey = wallet.getKeyForCoin(coin: .ethereum) else {
            throw WalletError.addressDerivationFailed
        }

        // Get private key for storage
        let privateKeyHex = derivedKey.data.hexString

        // Store in Pass vault
        let walletItem = PassCryptoWalletItem.create(
            name: "Ethereum Wallet",
            address: addressString,
            seedPhrase: mnemonics,
            privateKey: privateKeyHex,
            publicKey: addressString
        )

        // The create sheet's .task is our caller — dismissing the sheet
        // cancels it. Past this point we mutate shared state (vault, reveal
        // flag, address cache); if the user already cancelled, stop cleanly
        // instead of persisting a wallet they never saw.
        try Task.checkCancellation()

        try await passService.addItem(.cryptoWallet(walletItem))

        // Hold CryptoView on the onboarding flow until the recovery phrase
        // has been shown — set before the walletAddresses append flips
        // hasWallets. Skipped when the sheet was dismissed while the vault
        // PUT was in flight: its onDismiss (completeRecoveryPhraseReveal)
        // has already fired, so setting the flag now would strand it true
        // with nothing left to clear it.
        if !Task.isCancelled {
            pendingRecoveryPhraseReveal = true
        }

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

        // Returns nil on a phrase that fails BIP39 wordlist or checksum
        // validation, which is the only seed-phrase rejection we need.
        guard let wallet = HDWallet(mnemonic: trimmed, passphrase: "") else {
            Log.wallet.error("BIP39 seed phrase failed validation")
            throw WalletError.invalidSeedPhrase
        }

        guard let addressString = wallet.getAddressForCoin(coin: .ethereum),
              let derivedKey = wallet.getKeyForCoin(coin: .ethereum) else {
            throw WalletError.addressDerivationFailed
        }

        let privateKeyHex = derivedKey.data.hexString

        let walletItem = PassCryptoWalletItem.create(
            name: "Imported Wallet",
            address: addressString,
            seedPhrase: trimmed,
            privateKey: privateKeyHex,
            publicKey: addressString
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

        guard let keyData = Data(hexString: cleanKey) else {
            throw WalletError.invalidPrivateKey
        }

        // Rejects anything that is not a valid secp256k1 scalar — wrong
        // length, zero, or >= the curve order.
        guard let privateKey = PrivateKey(data: keyData) else {
            Log.wallet.error("Private key failed secp256k1 validation")
            throw WalletError.invalidPrivateKey
        }

        // Ethereum addresses come from the UNCOMPRESSED public key: keccak256
        // of its 64 body bytes, last 20 taken. Passing compressed: true here
        // yields a different, wrong address.
        let addressString = AnyAddress(
            publicKey: privateKey.getPublicKeySecp256k1(compressed: false),
            coin: .ethereum
        ).description

        let walletItem = PassCryptoWalletItem.create(
            name: "Imported Wallet",
            address: addressString,
            privateKey: cleanKey,
            publicKey: addressString
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
              let privateKeyData = Data(hexString: privateKeyHex) else {
            throw WalletError.privateKeyNotFound
        }

        guard AnyAddress.isValid(string: to, coin: .ethereum) else {
            Log.wallet.error("Invalid recipient address: \(to, privacy: .public)")
            throw WalletError.invalidRecipient
        }

        // Every numeric field is a big-endian uint256 byte string, which is
        // exactly BigUInt.serialize(). Zero serialises to empty Data, and RLP
        // encodes zero as the empty string, so that is the correct wire form
        // rather than a missing value.
        let input = EthereumSigningInput.with {
            $0.chainID = chainId.serialize()
            $0.nonce = nonce.serialize()
            // txMode left unset: Legacy, matching the EIP-155 transaction
            // web3swift produced here. Switching to .enveloped would emit a
            // type-2 (EIP-1559) transaction and break every signature vector.
            $0.gasPrice = gasPrice.serialize()
            $0.gasLimit = gasLimit.serialize()
            $0.toAddress = to
            $0.privateKey = privateKeyData
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = value.serialize()
                    $0.data = data
                }
            }
        }

        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)

        // AnySigner does not throw. A failed sign returns an output carrying a
        // non-zero error and empty `encoded` (TW.Common.Proto.SigningError,
        // where OK = 0), so without this check a signing failure would surface
        // as a silently empty transaction.
        guard output.error.rawValue == 0, !output.encoded.isEmpty else {
            Log.wallet.error(
                "Transaction signing failed (\(output.error.rawValue, privacy: .public)): \(output.errorMessage, privacy: .public)"
            )
            throw WalletError.transactionSigningFailed
        }

        return output.encoded
    }

    // MARK: - Token Transfers

    /// The `transfer(address,uint256)` payload for an ERC-20 transfer.
    ///
    /// Needed *before* signing: what a token transfer costs in gas depends on
    /// the contract's own bookkeeping, so `eth_estimateGas` has to be handed
    /// the real payload to measure it. The 21000 that covers a plain ETH send
    /// never covers a contract call, and an under-estimate does not save
    /// money — the transaction runs out of gas and is charged for the attempt.
    static func erc20TransferCallData(to: String, amount: BigUInt) throws -> Data {
        guard let recipient = AnyAddress(string: to, coin: .ethereum) else {
            throw WalletError.invalidRecipient
        }
        let function = EthereumAbiFunction(name: "transfer")
        function.addParamAddress(val: recipient.data, isOutput: false)
        function.addParamUInt256(val: amount.serialize(), isOutput: false)
        return EthereumAbi.encode(fn: function)
    }

    /// Sign an ERC-20 token transfer (requires Pass vault to be unlocked).
    ///
    /// A token is not held by the network — it is a row in a ledger owned by
    /// the token's contract, so moving it is a *call to that contract*, not a
    /// payment to the recipient. Three things follow, and all three differ from
    /// `signTransaction`:
    ///
    /// - the transaction goes **to the contract**, not to `to`;
    /// - it carries **no ETH** (`value` is absent), because no ETH moves;
    /// - the recipient and the amount travel inside the call payload.
    ///
    /// `amount` is already in the token's base units — see `TokenAmount`. The
    /// token's own `decimals` decide that scale, and assuming ETH's 18 for a
    /// 6-decimal token overstates a transfer by a factor of a trillion.
    func signTokenTransfer(
        tokenContract: String,
        to: String,
        amount: BigUInt,
        nonce: BigUInt,
        gasPrice: BigUInt,
        gasLimit: BigUInt,
        chainId: BigUInt = 1,
        fromAddress: String
    ) throws -> Data {
        guard let privateKeyHex = getPrivateKey(for: fromAddress),
              let privateKeyData = Data(hexString: privateKeyHex) else {
            throw WalletError.privateKeyNotFound
        }

        guard AnyAddress.isValid(string: tokenContract, coin: .ethereum) else {
            Log.wallet.error("Invalid token contract: \(tokenContract, privacy: .public)")
            throw WalletError.invalidTokenContract
        }

        guard AnyAddress.isValid(string: to, coin: .ethereum) else {
            Log.wallet.error("Invalid recipient address: \(to, privacy: .public)")
            throw WalletError.invalidRecipient
        }

        let input = EthereumSigningInput.with {
            $0.chainID = chainId.serialize()
            $0.nonce = nonce.serialize()
            // Legacy, as in signTransaction — see the note there.
            $0.gasPrice = gasPrice.serialize()
            $0.gasLimit = gasLimit.serialize()
            // The contract is the destination. The person being paid appears
            // only inside erc20Transfer below.
            $0.toAddress = tokenContract
            $0.privateKey = privateKeyData
            $0.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = to
                    $0.amount = amount.serialize()
                }
            }
        }

        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)

        guard output.error.rawValue == 0, !output.encoded.isEmpty else {
            Log.wallet.error(
                "Token transfer signing failed (\(output.error.rawValue, privacy: .public)): \(output.errorMessage, privacy: .public)"
            )
            throw WalletError.transactionSigningFailed
        }

        return output.encoded
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
    case invalidTokenContract
    case amountTooPrecise(allowed: Int)
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
        case .invalidTokenContract: "Invalid token contract address"
        case .amountTooPrecise(let allowed):
            allowed == 0
                ? "This token cannot be split — enter a whole number"
                : "This token supports at most \(allowed) decimal places"
        case .privateKeyNotFound: "Private key not found in vault"
        case .transactionSigningFailed: "Failed to sign transaction"
        case .walletNotFound: "Wallet not found in vault"
        }
    }
}
