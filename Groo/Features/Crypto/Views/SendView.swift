//
//  SendView.swift
//  Groo
//
//  Send ETH or an ERC-20 token to another address. The two are different
//  transactions, not one with a flag — see sendTransaction().
//

import BigInt
import os
import Security
import SwiftUI
import WalletCore

struct SendView: View {
    let asset: CryptoAsset
    let walletManager: WalletManager
    let ethereumService: EthereumService
    let passService: PassService

    @Environment(\.dismiss) private var dismiss

    @State private var recipientAddress = ""
    @State private var amount = ""
    @State private var gasEstimate: String?
    @State private var gasPrice: String?
    @State private var isEstimatingGas = false
    @State private var isSending = false
    @State private var txHash: String?
    @State private var error: String?
    @State private var showConfirm = false
    @State private var showUnlockPrompt = false

    /// For display only — the price line and the balance check. Never for
    /// building a transaction: see `amountBaseUnits`.
    private var amountDouble: Double {
        Double(amount) ?? 0
    }

    /// The typed amount in the asset's own base units, or nil if it is not a
    /// usable number. This is what a transaction carries.
    private var amountBaseUnits: BigUInt? {
        try? TokenAmount.baseUnits(from: amount, decimals: asset.decimals)
    }

    /// Set only when the amount is well-formed but finer than the token can
    /// represent, so the field can say why rather than just refusing.
    private var amountPrecisionWarning: String? {
        do {
            _ = try TokenAmount.baseUnits(from: amount, decimals: asset.decimals)
            return nil
        } catch TokenAmount.ParseError.tooManyFractionalDigits(let allowed) {
            return WalletError.amountTooPrecise(allowed: allowed).errorDescription
        } catch {
            return nil
        }
    }

    /// A 42-character string beginning "0x" is not an address — "0x" plus 40
    /// spaces passes that test. Ask the library that will have to encode it.
    private var isValidAddress: Bool {
        AnyAddress.isValid(string: recipientAddress, coin: .ethereum)
    }

    private var gasCostEth: Double {
        guard let gas = gasEstimate, let price = gasPrice,
              let gasValue = hexToUInt64(gas),
              let priceValue = hexToUInt64(price) else { return 0 }
        return Double(gasValue * priceValue) / 1e18
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if let txHash {
                // Success state
                successView(txHash: txHash)
            } else {
                // Send form
                sendForm
            }
        }
        .navigationTitle("Send \(asset.symbol)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Unlock Pass", isPresented: $showUnlockPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Unlock") {
                Task {
                    do {
                        _ = try await passService.unlockWithBiometric()
                    } catch KeychainError.loadFailed(errSecUserCanceled) {
                        // User cancelled the biometric prompt — nothing to surface
                    } catch {
                        Log.wallet.error("Biometric unlock failed: \(String(describing: error))")
                        self.error = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Pass vault must be unlocked to sign transactions.")
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

    // MARK: - Send Form

    private var sendForm: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Recipient")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("0x...", text: $recipientAddress)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("MAX") {
                        amount = String(asset.balance)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Brand.primary)
                }

                HStack {
                    TextField("0.0", text: $amount)
                        .font(.title2)
                        .keyboardType(.decimalPad)

                    Text(asset.symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                if let amountPrecisionWarning {
                    Text(amountPrecisionWarning)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if amountDouble > 0 {
                    Text("\(formatCurrency(amountDouble * asset.price))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Gas estimate
            if isEstimatingGas {
                HStack {
                    ProgressView()
                    Text("Estimating gas...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if gasCostEth > 0 {
                HStack {
                    Text("Estimated Gas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.6f ETH", gasCostEth))
                        .font(.caption.monospaced())
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            Spacer()

            // Send button
            Button {
                if passService.isUnlocked {
                    Task { await estimateAndConfirm() }
                } else {
                    showUnlockPrompt = true
                }
            } label: {
                if isSending {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Brand.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                } else {
                    Text("Send")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSend ? Theme.Brand.primary : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
            .disabled(!canSend || isSending)
            .padding(.horizontal)
        }
        .padding()
        .confirmationDialog("Confirm Transaction", isPresented: $showConfirm) {
            Button("Send \(amount) \(asset.symbol)") {
                Task { await sendTransaction() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Send \(amount) \(asset.symbol) to \(recipientAddress.prefix(8))...\(recipientAddress.suffix(4))\nGas: ~\(String(format: "%.6f", gasCostEth)) ETH")
        }
    }

    // MARK: - Success View

    private func successView(txHash: String) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.Size.iconHero))
                .foregroundStyle(.green)

            Text("Transaction Sent!")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: Theme.Spacing.xs) {
                Text("Transaction Hash")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(txHash)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .padding(.horizontal)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Brand.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        isValidAddress
            && amountDouble > 0
            && amountDouble <= asset.balance
            && amountBaseUnits != nil
    }

    private func estimateAndConfirm() async {
        isEstimatingGas = true
        defer { isEstimatingGas = false }

        guard let address = walletManager.activeAddress else {
            error = "No active wallet"
            return
        }

        let units: BigUInt
        do {
            units = try TokenAmount.baseUnits(from: amount, decimals: asset.decimals)
        } catch TokenAmount.ParseError.tooManyFractionalDigits(let allowed) {
            error = WalletError.amountTooPrecise(allowed: allowed).errorDescription
            return
        } catch {
            // `error` here is the caught value; the state property needs self.
            self.error = "Enter a valid amount"
            return
        }

        do {
            // What a transfer costs in gas depends on what it does. A plain
            // send is a fixed 21000; a token transfer is the contract's own
            // bookkeeping, which only the node can price — and only if it is
            // given the actual call payload to run.
            let destination: String
            let value: String
            let callData: String
            if let contract = asset.contractAddress {
                destination = contract
                value = "0x0"   // no ETH moves in a token transfer
                callData = "0x" + (try WalletManager.erc20TransferCallData(
                    to: recipientAddress, amount: units)).hexString
            } else {
                destination = recipientAddress
                value = "0x" + String(units, radix: 16)
                callData = "0x"
            }

            async let gasEstimateTask = ethereumService.estimateGas(
                from: address,
                to: destination,
                value: value,
                data: callData
            )
            async let gasPriceTask = ethereumService.getGasPrice()

            gasEstimate = try await gasEstimateTask
            gasPrice = try await gasPriceTask

            showConfirm = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendTransaction() async {
        isSending = true
        defer { isSending = false }

        guard let address = walletManager.activeAddress else {
            error = "No active wallet"
            return
        }

        guard let gasPriceHex = gasPrice else {
            Log.wallet.error("Send aborted: gas price unavailable")
            error = "Gas price unavailable"
            return
        }

        do {
            let nonceHex = try await ethereumService.getTransactionCount(address: address)

            // A plain send always costs 21000, so falling back to it is safe.
            // A contract call has no safe default: guessing one buys an
            // out-of-gas transaction, which fails and is charged for anyway.
            let gasLimitHex: String
            if asset.contractAddress == nil {
                gasLimitHex = gasEstimate ?? "0x5208" // 21000 default
            } else if let estimate = gasEstimate {
                gasLimitHex = estimate
            } else {
                Log.wallet.error("Send aborted: no gas estimate for a token transfer")
                error = "Could not estimate the network fee — send aborted"
                return
            }

            guard let nonce = hexToUInt64(nonceHex),
                  let gasPriceValue = hexToUInt64(gasPriceHex),
                  let gasLimitValue = hexToUInt64(gasLimitHex) else {
                Log.wallet.error("Send aborted: failed to parse transaction parameters — nonce=\(nonceHex, privacy: .public) gasPrice=\(gasPriceHex, privacy: .public) gasLimit=\(gasLimitHex, privacy: .public)")
                error = "Could not read transaction parameters — send aborted"
                return
            }

            let units = try TokenAmount.baseUnits(from: amount, decimals: asset.decimals)

            // Two different transactions. A token is a row in the contract's
            // ledger, so moving it is a call to that contract carrying no ETH;
            // only a native send pays the recipient directly.
            let signedTx: Data
            if let contract = asset.contractAddress {
                signedTx = try walletManager.signTokenTransfer(
                    tokenContract: contract,
                    to: recipientAddress,
                    amount: units,
                    nonce: BigUInt(nonce),
                    gasPrice: BigUInt(gasPriceValue),
                    gasLimit: BigUInt(gasLimitValue),
                    fromAddress: address
                )
            } else {
                signedTx = try walletManager.signTransaction(
                    to: recipientAddress,
                    value: units,
                    nonce: BigUInt(nonce),
                    gasPrice: BigUInt(gasPriceValue),
                    gasLimit: BigUInt(gasLimitValue),
                    fromAddress: address
                )
            }

            let hash = try await ethereumService.sendRawTransaction(
                signedTx: signedTx.hexString
            )
            txHash = hash
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func hexToUInt64(_ hex: String) -> UInt64? {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return UInt64(clean, radix: 16)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
