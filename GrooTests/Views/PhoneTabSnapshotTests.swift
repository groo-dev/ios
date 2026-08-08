//
//  PhoneTabSnapshotTests.swift
//  GrooTests
//
//  The iPhone sibling renders: default configuration, a Home-disabled
//  configuration, the More screen, and the editor. Render-only (tab content
//  refreshes via .task against dead URLs), matching RootViewSnapshotTests.
//

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct PhoneTabSnapshotTests {
    private func makeStore(json: String? = nil) throws -> (TabConfigurationStore, UserDefaults, String) {
        let suiteName = "phonetab-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        if let json { defaults.set(json, forKey: TabConfigurationStore.defaultsKey) }
        return (TabConfigurationStore(defaults: defaults), defaults, suiteName)
    }

    @Test func phoneTabViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            ViewRender.assertRenders(
                PhoneTabView(padService: padService,
                             syncService: PadViewSnapshotTests.offlineSync(store: store),
                             passService: passEnv.service, onSignOut: {})
                    .environment(AuthService())
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    @Test func phoneTabViewWithHomeDisabledRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let (configStore, defaults, suite) = try makeStore(
            json: #"{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":false}"#)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(configStore.configuration.barTabs == [.azan, .pass, .pad, .stocks])

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            ViewRender.assertRenders(
                PhoneTabView(padService: padService,
                             syncService: PadViewSnapshotTests.offlineSync(store: store),
                             passService: passEnv.service, onSignOut: {})
                    .environment(AuthService())
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    @Test func moreViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let content = FeatureContent(
            padService: padService,
            syncService: PadViewSnapshotTests.offlineSync(store: store),
            passService: passEnv.service,
            onSignOut: {},
            onLock: {}
        )

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            ViewRender.assertRenders(
                MoreView(configuration: configStore.configuration,
                         content: content,
                         path: .constant([]))
                    .environment(AuthService()))
        }
    }

    // Fix-wave finding 3: Pad dragged past the cut and opened from More while
    // locked must keep a visible back button — PadUnlockView's unconditional
    // .toolbar(.hidden, for: .navigationBar) (there to preserve tab-root
    // appearance) previously suppressed it here too, leaving edge-swipe as
    // the only way back with no visible affordance. Pixel snapshot with an
    // initial path of [.pad] renders the pushed PadUnlockView directly (no
    // animation needed — it is the stack's initial state, not a transition).
    @Test func moreViewPushedPadUnlockKeepsNavigationBar() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }

        let content = FeatureContent(
            padService: padService,
            syncService: PadViewSnapshotTests.offlineSync(store: store),
            passService: passEnv.service,
            onSignOut: {},
            onLock: {}
        )

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            assertViewSnapshot(
                of: MoreView(
                    configuration: .default,
                    content: content,
                    path: .constant([.pad])
                )
                .environment(AuthService()),
                named: "pushedPadUnlock")
        }
    }

    // The pixel snapshot above is a content regression net, but a titleless,
    // back-button-less bar renders identically whether UIKit considers it
    // shown or hidden — no pixel would move if this fix were reverted. Pin
    // the actual toolbar state via the UINavigationController SwiftUI
    // creates internally so a regression is caught even though it would be
    // visually silent here.
    @Test func moreViewPushedPadUnlockKeepsNavigationBarStructurally() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }

        let content = FeatureContent(
            padService: padService,
            syncService: PadViewSnapshotTests.offlineSync(store: store),
            passService: passEnv.service,
            onSignOut: {},
            onLock: {}
        )

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            let nav = ViewRender.navigationController(
                hosting: MoreView(configuration: .default, content: content, path: .constant([.pad]))
                    .environment(AuthService()))
            #expect(nav?.isNavigationBarHidden == false)
        }
    }

    // Contrast case: Pad rendered as a tab root (never pushed from More)
    // must still hide the bar — pinning that the isPushedDestination fix
    // does not accidentally show it everywhere.
    @Test func padUnlockAsTabRootStillHidesNavigationBar() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()

        let nav = ViewRender.navigationController(
            hosting: NavigationStack {
                PadUnlockView(padService: padService,
                              syncService: PadViewSnapshotTests.offlineSync(store: store),
                              onUnlock: {}, onSignOut: {})
            })
        #expect(nav?.isNavigationBarHidden == true)
    }

    @Test func tabBarEditorRendersOnly() throws {
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        ViewRender.assertRenders(
            NavigationStack { PhoneTabBarEditor() }
                .environment(configStore))
    }
}
}
