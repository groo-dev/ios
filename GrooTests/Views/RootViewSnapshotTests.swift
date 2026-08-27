//
//  RootViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: root screens. AuthService is injected bare (constructible
//  without side effects — the preview pattern); Pad/Pass services are the
//  standard fakes; Config base URLs are pinned to a dead loopback port so
//  HomeView's refresh tasks fail fast without leaving the process.
//

import GrooAuthUI
import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct RootViewSnapshotTests {
    static let deadURLDefaults: [String: Any] = [
        "padAPIBaseURL": "http://127.0.0.1:9",
        "passAPIBaseURL": "http://127.0.0.1:9",
        "accountsAPIBaseURL": "http://127.0.0.1:9",
        "ethereumRPCURL": "http://127.0.0.1:9",
        "blockscoutBaseURL": "http://127.0.0.1:9",
        "coinGeckoBaseURL": "http://127.0.0.1:9",
        "displayCurrency": "USD",
        "selectedTab": "home",
    ]

    @Test func signInScreen() {
        // The theme comes from GrooApp in production, so the test supplies it
        // rather than the screen carrying its own copy.
        assertViewSnapshot(
            of: SignInScreen().environment(AuthService()).environment(\.grooAuthTheme, .grooApp),
            named: "logged-out"
        )
    }

    @Test func unlockView() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        assertViewSnapshot(
            of: UnlockView(padService: padService,
                           syncService: PadViewSnapshotTests.offlineSync(store: store),
                           onUnlock: {}, onSignOut: {})
                .environment(AuthService()),
            named: "locked")
    }

    @Test func globalLockView() throws {
        StubURLProtocol.reset()
        let (padService, _) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        // onAppear schedules unlockAll() at +0.3s — it runs against the
        // fakes AFTER the draw and cannot affect the committed image.
        assertViewSnapshot(
            of: GlobalLockView(padService: padService, passService: passEnv.service,
                               onUnlock: {}, onSignOut: {}),
            named: "locked")
    }

    // SettingsView renders GrooUserButton, and the theme reaches it from GrooApp
    // in production. A snapshot taken without it pictures a green avatar this app
    // never shows — which is how the missing theme was noticed in the first place.
    @Test func settingsView() async throws {
        StubURLProtocol.reset()
        let (padService, _) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        await withPinnedDefaults(Self.deadURLDefaults) {
            await assertSettledViewSnapshot(
                of: NavigationStack {
                    SettingsView(padService: padService, passService: passEnv.service,
                                 onSignOut: {}, onLock: {})
                }
                .environment(AuthService())
                .environment(\.grooAuthTheme, .grooApp),
                named: "default")
        }
    }

    // Gap-menu follow-on (P7 Task 9): SettingsView's `if let date =
    // lastBackupDate` branch — loadLastBackupDate() (called from the
    // view's own .task, after loadBiometricState()) finds an unlocked
    // vault's "Stock Portfolio Backup" note and populates the date label.
    @Test func settingsViewWithBackupDate() async throws {
        StubURLProtocol.reset()
        let (padService, _) = try PadViewSnapshotTests.lockedPadService()
        let backupNote = PassVaultItem.note(PassNoteItem(
            id: "note-backup", type: .note, name: "Stock Portfolio Backup",
            content: "{}", folderId: nil, favorite: nil,
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000, deletedAt: nil))
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [backupNote])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        _ = try await passEnv.service.unlock(password: PassServiceIntegrationTests.password)
        await withPinnedDefaults(Self.deadURLDefaults) {
            await assertSettledViewSnapshot(
                of: NavigationStack {
                    SettingsView(padService: padService, passService: passEnv.service,
                                 onSignOut: {}, onLock: {})
                }
                .environment(AuthService())
                .environment(\.grooAuthTheme, .grooApp),
                named: "backup-date")
        }
    }

    @Test func homeViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let suiteName = "homeview-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = TabConfigurationStore(defaults: defaults)
        withPinnedDefaults(Self.deadURLDefaults) {
            // Live prayer countdown + shared-store cache reads — render-only.
            ViewRender.assertRenders(
                HomeView(padService: padService,
                         syncService: PadViewSnapshotTests.offlineSync(store: store),
                         passService: passEnv.service)
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    // Gap-menu follow-on (P7 Task 9): HomeView's Pad card unlocked branches
    // (padService.isUnlocked, gated by loadCachedData()'s synchronous
    // onAppear reloadPadItems() — no .task/network involved) — populated
    // (up to 3 rows) and empty. Live prayer countdown elsewhere → render-only.
    @Test func homeViewPadUnlockedRendersOnly() throws {
        StubURLProtocol.reset()
        let padEnv = try PadServiceTests.makeUnlockedEnv()
        try PadViewSnapshotTests.seedItem(padEnv, id: "i-1", text: "Wifi password: hunter2")
        try PadViewSnapshotTests.seedItem(padEnv, id: "i-2", text: "Locker combo: 12-34-56")
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let suiteName = "homeview-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = TabConfigurationStore(defaults: defaults)
        withPinnedDefaults(Self.deadURLDefaults) {
            ViewRender.assertRenders(
                HomeView(padService: padEnv.service,
                         syncService: PadViewSnapshotTests.offlineSync(store: padEnv.store),
                         passService: passEnv.service)
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    @Test func homeViewPadUnlockedEmptyRendersOnly() throws {
        StubURLProtocol.reset()
        let padEnv = try PadServiceTests.makeUnlockedEnv()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let suiteName = "homeview-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = TabConfigurationStore(defaults: defaults)
        withPinnedDefaults(Self.deadURLDefaults) {
            ViewRender.assertRenders(
                HomeView(padService: padEnv.service,
                         syncService: PadViewSnapshotTests.offlineSync(store: padEnv.store),
                         passService: passEnv.service)
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    // Gap-menu follow-on (P7 Task 9): HomeView's crypto-card wallet branch —
    // loadCachedData() builds WalletManager over UserDefaults.standard, so
    // pinning walletAddresses/activeWalletAddress flips hasWallets and the
    // "Open wallet" sub-branch renders. Render-only (the card's
    // sparkline/total refresh via .task against the dead URLs).
    @Test func homeViewCryptoWalletCardRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let address = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B"
        let suiteName = "homeview-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = TabConfigurationStore(defaults: defaults)
        withPinnedDefaults(Self.deadURLDefaults.merging(
            ["walletAddresses": address, "activeWalletAddress": address]) { _, new in new }) {
            ViewRender.assertRenders(
                HomeView(padService: padService,
                         syncService: PadViewSnapshotTests.offlineSync(store: store),
                         passService: passEnv.service)
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    @Test func mainTabViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let suiteName = "maintab-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = TabConfigurationStore(defaults: defaults)
        withPinnedDefaults(Self.deadURLDefaults) {
            ViewRender.assertRenders(
                MainTabView(padService: padService,
                            syncService: PadViewSnapshotTests.offlineSync(store: store),
                            passService: passEnv.service, onSignOut: {})
                    .environment(AuthService())
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    // Gap-menu lever 1 (P7 Task 9): ContentView's !isLoggedIn branch — the
    // real root view (not LoginView directly), exercising ContentView's own
    // body/onAppear/initializeServices path when no auth session exists.
    @Test func contentViewLoggedOutRendersOnly() {
        StubURLProtocol.reset()
        ViewRender.assertRenders(
            ContentView().environment(AuthService()).environment(PushService()))
    }
}
}
