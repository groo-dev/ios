//
//  PhoneTabSnapshotTests.swift
//  GrooTests
//
//  The iPhone sibling renders: default configuration, a Home-disabled
//  configuration, the More screen, and the editor. Render-only (tab content
//  refreshes via .task against dead URLs), matching RootViewSnapshotTests.
//

import Foundation
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

    @Test func tabBarEditorRendersOnly() throws {
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        ViewRender.assertRenders(
            NavigationStack { PhoneTabBarEditor() }
                .environment(configStore))
    }
}
}
