//
//  SendView.swift
//  Groo
//
//  Send ETH or ERC-20 tokens to another address.
//

import BigInt
import CryptoSwift
import SwiftUI
import Web3Core
import web3swift

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

    private var amountDouble: Double {
        Double(amount) ?? 0
    }

    private var isValidAddress: Bool {
        recipientAddress.hasPrefix("0x") && recipientAddress.count == 42
    }

    private var gasCostEth: Double {
        guard let gas = gasEstimate, let price = gasPrice else { return 0 }
        let gasValue = hexToUInt64(gas)
        let priceValue = hexToUInt64(price)
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
                Task { try? await passService.unlockWithBiometric() }
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

                if amountDouble > 0 {
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
        isValidAddress && amountDouble > 0 && amountDouble <= asset.balance
    }

    private func estimateAndConfirm() async {
        isEstimatingGas = true
        defer { isEstimatingGas = false }

        guard let address = walletManager.activeAddress else { return }

        let weiHex = ethToHex(amountDouble)

        do {
            async let gasEstimateTask = ethereumService.estimateGas(
                from: address,
                to: recipientAddress,
                value: weiHex
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

        guard let address = walletManager.activeAddress else { return }

        do {
            let nonce = try await ethereumService.getTransactionCount(address: address)
            let gasLimitValue = gasEstimate ?? "0x5208" // 21000 default
            let gasPriceValue = gasPrice ?? "0x0"

            let signedTx = try walletManager.signTransaction(
                to: recipientAddress,
                value: BigUInt(amountDouble * 1e18),
                nonce: BigUInt(hexToUInt64(nonce)),
                gasPrice: BigUInt(hexToUInt64(gasPriceValue)),
                gasLimit: BigUInt(hexToUInt64(gasLimitValue)),
                fromAddress: address
            )

            let hash = try await ethereumService.sendRawTransaction(
                signedTx: signedTx.toHexString()
            )
            txHash = hash
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func hexToUInt64(_ hex: String) -> UInt64 {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return UInt64(clean, radix: 16) ?? 0
    }

    private func ethToHex(_ eth: Double) -> String {
        let wei = UInt64(eth * 1e18)
        return "0x" + String(wei, radix: 16)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
