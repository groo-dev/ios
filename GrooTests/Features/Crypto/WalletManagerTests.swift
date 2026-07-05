//
//  WalletManagerTests.swift
//  GrooTests
//
//  BIP39 import vectors, wallet lifecycle against an unlocked stubbed vault.
//  Vector failures mean a derivation regression — never adjust the constants.
//

import BigInt
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct WalletManagerTests {
    static let vectorMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    static let vectorMnemonicAddress = "0x9858effd232b4033e47d90003d41ec34ecaeda94"
    static let vectorPrivateKey = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
    static let vectorPrivateKeyAddress = "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"

    struct WalletEnv {
        let manager: WalletManager
        let env: PassServiceIntegrationTests.Env
        let defaults: UserDefaults
        let suiteName: String
    }

    /// Unlocked PassService (stubbed network) + WalletManager on isolated UserDefaults.
    static func makeWalletEnv() async throws -> WalletEnv {
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        PassServiceIntegrationTests.stubVaultPut(version: 4)

        let suiteName = "WalletManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = WalletManager(passService: env.service, defaults: defaults)
        return WalletEnv(manager: manager, env: env, defaults: defaults, suiteName: suiteName)
    }

    static func tearDown(_ walletEnv: WalletEnv) {
        walletEnv.defaults.removePersistentDomain(forName: walletEnv.suiteName)
        try? FileManager.default.removeItem(at: walletEnv.env.tempDir)
    }

    // MARK: - Import vectors

    @Test func importSeedPhraseDerivesKnownAddress() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let address = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)

        #expect(address.lowercased() == Self.vectorMnemonicAddress,
                "BIP39 vector mismatch — derived \(address); derivation path assumption is wrong, STOP and report")
        #expect(walletEnv.manager.walletAddresses.map { $0.lowercased() } == [Self.vectorMnemonicAddress])
        #expect(walletEnv.manager.hasWallets)

        // Vault item stored with the seed phrase and a private key
        let items = walletEnv.manager.getWalletItems()
        #expect(items.count == 1)
        #expect(items.first?.seedPhrase == Self.vectorMnemonic)
        #expect(items.first?.privateKey?.isEmpty == false)
    }

    @Test func importSeedPhraseNormalizesWhitespace() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let messy = "  abandon abandon  abandon\nabandon abandon abandon abandon abandon abandon abandon abandon   about  "
        let address = try await walletEnv.manager.importWallet(seedPhrase: messy)

        #expect(address.lowercased() == Self.vectorMnemonicAddress)
    }

    @Test func importInvalidSeedPhraseThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        await #expect(throws: (any Error).self) {
            _ = try await walletEnv.manager.importWallet(seedPhrase: "definitely not a valid mnemonic phrase at all twelve")
        }
        #expect(!walletEnv.manager.hasWallets)
    }

    @Test func importPrivateKeyDerivesKnownAddress() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let address = try await walletEnv.manager.importWallet(privateKey: "0x" + Self.vectorPrivateKey)

        #expect(address.lowercased() == Self.vectorPrivateKeyAddress,
                "private-key vector mismatch — derived \(address); STOP and report")
        // 0x prefix stripped before storage
        #expect(walletEnv.manager.getPrivateKey(for: address) == Self.vectorPrivateKey)
    }

    @Test func importInvalidPrivateKeyThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        await #expect {
            _ = try await walletEnv.manager.importWallet(privateKey: "zz-not-hex")
        } throws: { error in
            guard case WalletError.invalidPrivateKey = error else { return false }
            return true
        }
    }

    // MARK: - Create

    @Test func createWalletProducesReimportableMnemonic() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let (mnemonic, address) = try await walletEnv.manager.createWallet()

        #expect(mnemonic.split(separator: " ").count == 12)   // 128 bits of entropy
        #expect(address.hasPrefix("0x") && address.count == 42)
        #expect(walletEnv.manager.activeAddress == address)

        // Determinism roundtrip: re-importing the mnemonic derives the same address
        let walletEnv2 = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv2) }
        let reimported = try await walletEnv2.manager.importWallet(seedPhrase: mnemonic)
        #expect(reimported.lowercased() == address.lowercased())
    }

    // MARK: - Address cache & active address

    @Test func addressesPersistAcrossManagerInstances() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)

        // New manager over the same defaults sees the cached address without vault access
        let reborn = WalletManager(passService: walletEnv.env.service, defaults: walletEnv.defaults)
        #expect(reborn.walletAddresses.map { $0.lowercased() } == [Self.vectorMnemonicAddress])
        #expect(reborn.activeAddress?.lowercased() == Self.vectorMnemonicAddress)
    }

    @Test func setActiveAddressPersists() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)

        walletEnv.manager.setActiveAddress(Self.vectorPrivateKeyAddress)

        let reborn = WalletManager(passService: walletEnv.env.service, defaults: walletEnv.defaults)
        #expect(reborn.activeAddress == Self.vectorPrivateKeyAddress)
    }

    // MARK: - Signing

    @Test func signTransactionProducesRlpEncodedBytes() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)

        let signed = try walletEnv.manager.signTransaction(
            to: "0x3535353535353535353535353535353535353535",
            value: BigUInt(1_000_000_000_000_000_000),
            nonce: BigUInt(9),
            gasPrice: BigUInt(20_000_000_000),
            gasLimit: BigUInt(21_000),
            fromAddress: Self.vectorPrivateKeyAddress
        )

        #expect(!signed.isEmpty)
        #expect(signed.first == 0xf8)  // RLP list prefix for a legacy signed tx of this size
    }

    enum RLPError: Error { case malformed }

    /// Minimal RLP decoder for a top-level list of byte-string items — just
    /// enough to pull v/r/s out of a signed legacy transaction. Nested lists
    /// are rejected (a legacy tx has none).
    static func rlpListItems(_ data: Data) throws -> [Data] {
        let bytes = [UInt8](data)
        guard let first = bytes.first else { throw RLPError.malformed }

        var index: Int
        let end: Int
        if (0xc0...0xf7).contains(first) {
            index = 1
            end = index + Int(first - 0xc0)
        } else if first >= 0xf8 {
            let lengthOfLength = Int(first - 0xf7)
            guard bytes.count > lengthOfLength else { throw RLPError.malformed }
            let length = bytes[1...lengthOfLength].reduce(0) { $0 << 8 | Int($1) }
            index = 1 + lengthOfLength
            end = index + length
        } else {
            throw RLPError.malformed
        }
        guard end <= bytes.count else { throw RLPError.malformed }

        var items: [Data] = []
        while index < end {
            let marker = bytes[index]
            switch marker {
            case 0x00...0x7f:
                items.append(Data([marker]))
                index += 1
            case 0x80...0xb7:
                let length = Int(marker - 0x80)
                guard index + 1 + length <= end else { throw RLPError.malformed }
                items.append(Data(bytes[(index + 1)..<(index + 1 + length)]))
                index += 1 + length
            case 0xb8...0xbf:
                let lengthOfLength = Int(marker - 0xb7)
                guard index + 1 + lengthOfLength <= end else { throw RLPError.malformed }
                let length = bytes[(index + 1)...(index + lengthOfLength)].reduce(0) { $0 << 8 | Int($1) }
                guard index + 1 + lengthOfLength + length <= end else { throw RLPError.malformed }
                items.append(Data(bytes[(index + 1 + lengthOfLength)..<(index + 1 + lengthOfLength + length)]))
                index += 1 + lengthOfLength + length
            default:
                throw RLPError.malformed   // nested list — not valid in a legacy tx
            }
        }
        return items
    }

    /// A wallet signing for the wrong chain is a real failure mode: the
    /// signature would be valid on some other network and replayable there.
    /// EIP-155: v = chainId * 2 + 35 (+ recovery bit) → 37/38 for mainnet.
    @Test func signTransactionEmbedsChainId1InV() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)

        let signed = try walletEnv.manager.signTransaction(
            to: "0x3535353535353535353535353535353535353535",
            value: BigUInt(1_000_000_000_000_000_000),
            nonce: BigUInt(9),
            gasPrice: BigUInt(20_000_000_000),
            gasLimit: BigUInt(21_000),
            fromAddress: Self.vectorPrivateKeyAddress
        )

        // Legacy signed tx RLP: [nonce, gasPrice, gasLimit, to, value, data, v, r, s]
        let fields = try Self.rlpListItems(signed)
        #expect(fields.count == 9)
        let v = fields[6].reduce(BigUInt(0)) { $0 << 8 | BigUInt($1) }
        try #require(v >= 35, "expected an EIP-155 v, got \(v) — pre-EIP-155 signature has no replay protection")
        let chainId = (v - 35) / 2
        #expect(chainId == 1, "transaction signed for chainId \(chainId), not Ethereum mainnet (1) — wrong-chain signature")
    }

    @Test func signTransactionWithoutKeyThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        #expect {
            _ = try walletEnv.manager.signTransaction(
                to: "0x3535353535353535353535353535353535353535",
                value: BigUInt(1), nonce: BigUInt(0),
                gasPrice: BigUInt(1), gasLimit: BigUInt(21_000),
                fromAddress: "0x0000000000000000000000000000000000000001")
        } throws: { error in
            guard case WalletError.privateKeyNotFound = error else { return false }
            return true
        }
    }

    @Test func signTransactionRejectsInvalidRecipient() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)
        #expect {
            _ = try walletEnv.manager.signTransaction(
                to: "not-an-address",
                value: BigUInt(1), nonce: BigUInt(0),
                gasPrice: BigUInt(1), gasLimit: BigUInt(21_000),
                fromAddress: Self.vectorPrivateKeyAddress)
        } throws: { error in
            guard case WalletError.invalidRecipient = error else { return false }
            return true
        }
    }

    // MARK: - Rename / delete

    @Test func renameWalletUpdatesVaultItem() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        let address = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)

        try await walletEnv.manager.renameWallet(address: address.uppercased(), newName: "Cold Storage")

        #expect(walletEnv.manager.getWalletItems().first?.name == "Cold Storage")
    }

    @Test func renameUnknownWalletThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        await #expect {
            try await walletEnv.manager.renameWallet(address: "0xdead", newName: "x")
        } throws: { error in
            guard case WalletError.walletNotFound = error else { return false }
            return true
        }
    }

    @Test func deleteWalletRemovesItemCacheAndReassignsActive() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        let first = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)
        let second = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)
        walletEnv.manager.setActiveAddress(first)

        try await walletEnv.manager.deleteWallet(address: first)

        #expect(walletEnv.manager.walletAddresses.map { $0.lowercased() } == [second.lowercased()])
        #expect(walletEnv.manager.activeAddress?.lowercased() == second.lowercased())
        #expect(walletEnv.manager.getWalletItems().count == 1)
    }
}
}
