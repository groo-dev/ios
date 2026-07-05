//
//  CryptoViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Crypto views. Wallet state is
//  seeded through WalletManager's injected defaults (never scrypt);
//  services ride StubURLProtocol so nothing leaves the process.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct CryptoViewSnapshotTests {
    static let fixedMs = 1_700_000_000_000
    static let address = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B"

    static let ethAsset = CryptoAsset(
        id: "eth", symbol: "ETH", name: "Ethereum", balance: 1.5, price: 2000,
        priceChange24h: 2.5, iconURL: nil, decimals: 18, contractAddress: nil)
    static let tokenAsset = CryptoAsset(
        id: "0xa0b8", symbol: "USDC", name: "USD Coin", balance: 250, price: 1.0,
        priceChange24h: -0.1, iconURL: nil, decimals: 6,
        contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")

    static func pricePoints() -> [PricePoint] {
        (0..<24).map {
            PricePoint(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 3600),
                       price: 1900 + Double($0) * 10)
        }
    }

    static func walletItem(id: String, name: String, address: String) -> PassVaultItem {
        .cryptoWallet(PassCryptoWalletItem(
            id: id, type: .cryptoWallet, name: name, address: address,
            seedPhrase: "legal winner thank year wave sausage worth useful legal winner thank yellow",
            privateKey: nil, publicKey: nil, derivationPath: "m/44'/60'/0'/0/0",
            notes: nil, folderId: nil, favorite: nil,
            createdAt: fixedMs, updatedAt: fixedMs, deletedAt: nil))
    }

    struct WalletSetup {
        let manager: WalletManager
        let env: PassServiceIntegrationTests.Env
        let defaults: UserDefaults
        let suiteName: String
    }

    /// Unlocked fake vault + WalletManager over an isolated defaults suite
    /// with pre-seeded addresses — no scrypt, no network beyond the stubs.
    static func makeWalletSetup(items: [PassVaultItem], addresses: [String]) async throws -> WalletSetup {
        let env = try PassServiceIntegrationTests.makeEnv(items: items)
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        let suiteName = "CryptoSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(addresses.joined(separator: ","), forKey: "walletAddresses")
        if let first = addresses.first { defaults.set(first, forKey: "activeWalletAddress") }
        return WalletSetup(manager: WalletManager(passService: env.service, defaults: defaults),
                           env: env, defaults: defaults, suiteName: suiteName)
    }

    static func tearDown(_ setup: WalletSetup) {
        setup.defaults.removePersistentDomain(forName: setup.suiteName)
        try? FileManager.default.removeItem(at: setup.env.tempDir)
    }

    static func stubbedEthereum() -> EthereumService {
        EthereumService(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
    }

    static func stubbedCoinGecko() -> CoinGeckoService {
        CoinGeckoService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    // MARK: - Pure fixtures

    @Test func receiveViewQR() {
        assertViewSnapshot(of: NavigationStack { ReceiveView(address: Self.address) }, named: "address")
    }

    @Test func priceChartVariants() {
        let points = Self.pricePoints()
        assertViewSnapshot(
            of: PriceChartView(data: points, isLoading: false, isPositive: true,
                               errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            named: "positive", size: CGSize(width: 402, height: 300))
        assertViewSnapshot(
            of: PriceChartView(data: points.reversed(), isLoading: false, isPositive: false,
                               errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            named: "negative", size: CGSize(width: 402, height: 300))
        assertViewSnapshot(
            of: PriceChartView(data: [], isLoading: false, isPositive: true,
                               errorMessage: "Rate limited — try again later", selectedPoint: .constant(nil)).padding(),
            named: "error", size: CGSize(width: 402, height: 300))
        assertViewSnapshot(
            of: PriceChartView(data: [], isLoading: false, isPositive: true,
                               errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            named: "empty", size: CGSize(width: 402, height: 300))
        // isLoading spinner is indeterminate — render-only
        ViewRender.assertRenders(
            PriceChartView(data: [], isLoading: true, isPositive: true,
                           errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            size: CGSize(width: 402, height: 300))
    }

    // MARK: - Wallet-backed screens

    @Test func sendViewForAssets() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address)],
            addresses: [Self.address])
        defer { Self.tearDown(setup) }
        assertViewSnapshot(
            of: NavigationStack {
                SendView(asset: Self.ethAsset, walletManager: setup.manager,
                         ethereumService: Self.stubbedEthereum(), passService: setup.env.service)
            },
            named: "eth")
        assertViewSnapshot(
            of: NavigationStack {
                SendView(asset: Self.tokenAsset, walletManager: setup.manager,
                         ethereumService: Self.stubbedEthereum(), passService: setup.env.service)
            },
            named: "token")
    }

    @Test func walletOnboardingMain() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(items: [], addresses: [])
        defer { Self.tearDown(setup) }
        assertViewSnapshot(
            of: WalletOnboardingView(walletManager: setup.manager, passService: setup.env.service),
            named: "main")
    }

    @Test func walletListStates() async throws {
        StubURLProtocol.reset()
        let second = "0x00000000219ab540356cBB839Cbe05303d7705Fa"
        let populated = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address),
                    Self.walletItem(id: "w-2", name: "Savings", address: second)],
            addresses: [Self.address, second])
        defer { Self.tearDown(populated) }
        await assertSettledViewSnapshot(
            of: NavigationStack {
                WalletListView(walletManager: populated.manager, passService: populated.env.service)
            },
            named: "populated")

        // Locked PassService → unlock-prompt branch
        let lockedEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: lockedEnv.tempDir) }
        let lockedManager = WalletManager(passService: lockedEnv.service, defaults: populated.defaults)
        await assertSettledViewSnapshot(
            of: NavigationStack {
                WalletListView(walletManager: lockedManager, passService: lockedEnv.service)
            },
            named: "locked")
    }

    @Test func cryptoViewOnboardingState() async throws {
        StubURLProtocol.reset()
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        // CryptoView builds its own WalletManager over UserDefaults.standard —
        // pin the wallet keys empty so the onboarding branch is deterministic.
        let previousActive = UserDefaults.standard.object(forKey: "activeWalletAddress")
        UserDefaults.standard.removeObject(forKey: "activeWalletAddress")
        defer { if let previousActive { UserDefaults.standard.set(previousActive, forKey: "activeWalletAddress") } }
        await withPinnedDefaults(["walletAddresses": [String]()]) {
            await assertSettledViewSnapshot(
                of: CryptoView(passService: env.service), named: "onboarding")
        }
    }

    @Test func portfolioViewRendersOnly() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address)],
            addresses: [Self.address])
        defer { Self.tearDown(setup) }
        // Initial isLoading spinner + async portfolio load → render-only.
        await ViewRender.assertSettledRenders(
            NavigationStack {
                PortfolioView(walletManager: setup.manager, ethereumService: Self.stubbedEthereum(),
                              coinGeckoService: Self.stubbedCoinGecko(), passService: setup.env.service)
            })
    }

    @Test func assetDetailInitial() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address)],
            addresses: [Self.address])
        defer { Self.tearDown(setup) }
        // Header/stats/timeframe picker are deterministic; the chart's async
        // load lands post-draw (chartData starts empty).
        assertViewSnapshot(
            of: NavigationStack {
                AssetDetailView(asset: Self.ethAsset, walletManager: setup.manager,
                                ethereumService: Self.stubbedEthereum(),
                                coinGeckoService: Self.stubbedCoinGecko(),
                                passService: setup.env.service)
            },
            named: "initial")
    }
}
}
