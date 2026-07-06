//
//  RootViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: root screens. AuthService is injected bare (constructible
//  without side effects — the preview pattern); Pad/Pass services are the
//  standard fakes; Config base URLs are pinned to a dead loopback port so
//  HomeView's refresh tasks fail fast without leaving the process.
//

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

    @Test func loginView() {
        assertViewSnapshot(of: LoginView().environment(AuthService()), named: "logged-out")
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
                .environment(AuthService()),
                named: "default")
        }
    }

    @Test func homeViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        withPinnedDefaults(Self.deadURLDefaults) {
            // Live prayer countdown + shared-store cache reads — render-only.
            ViewRender.assertRenders(
                HomeView(padService: padService,
                         syncService: PadViewSnapshotTests.offlineSync(store: store),
                         passService: passEnv.service))
        }
    }

    @Test func mainTabViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        withPinnedDefaults(Self.deadURLDefaults) {
            ViewRender.assertRenders(
                MainTabView(padService: padService,
                            syncService: PadViewSnapshotTests.offlineSync(store: store),
                            passService: passEnv.service, onSignOut: {})
                    .environment(AuthService()))
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
