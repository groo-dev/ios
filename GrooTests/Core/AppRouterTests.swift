//
//  AppRouterTests.swift
//  GrooTests
//
//  open(_:) resolves against the live configuration: a feature in the bar is
//  selected directly, one past the cut selects More and pushes. Restore and
//  reconciliation must never strand the user on a tab that is not on screen.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct AppRouterTests {
    private func makeEnv() throws -> (AppRouter, TabConfigurationStore, UserDefaults, String) {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = TabConfigurationStore(defaults: defaults)
        return (AppRouter(store: store, defaults: defaults), store, defaults, suiteName)
    }

    @Test func openingABarFeatureSelectsItDirectly() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.pass)

        #expect(router.phoneSelection == .feature(.pass))
        #expect(router.morePath.isEmpty)
    }

    @Test func openingAFeaturePastTheCutSelectsMoreAndPushes() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(router.phoneSelection == .more)
        #expect(router.morePath == [.stocks])
    }

    @Test func openingAlwaysUpdatesThePadSelectionToo() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(router.padSelection == .stocks)
    }

    @Test func openingABarFeatureClearsAPreviousMorePush() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)
        router.open(.pad)

        #expect(router.phoneSelection == .feature(.pad))
        #expect(router.morePath.isEmpty)
    }

    @Test func restoringADemotedSelectionFallsBackToTheFirstBarTab() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Stocks is past the cut in the default configuration.
        defaults.set("stocks", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func restoringHomeWhenHomeIsDisabledFallsBackToTheFirstBarTab() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(#"{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":false}"#,
                     forKey: TabConfigurationStore.defaultsKey)
        defaults.set("home", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.azan))
    }

    @Test func restoringMoreIsHonoured() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("more", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .more)
    }

    @Test func settingsIsNeverARestorableFeatureSelection() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("settings", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func configurationChangeClearsThePathAndRevalidatesSelection() throws {
        let (router, store, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }
        router.open(.pass)

        var config = store.configuration
        config.move(fromOffsets: IndexSet(integer: 1), toOffset: 7)   // pass to the end
        store.configuration = config
        router.configurationDidChange()

        #expect(router.morePath.isEmpty)
        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func selectionIsPersistedOnWrite() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(defaults.string(forKey: AppRouter.selectionKey) == "more")
    }

    @Test func phoneSelectionStorageValueRoundTrips() {
        #expect(PhoneSelection(storageValue: "more") == .more)
        #expect(PhoneSelection(storageValue: "pass") == .feature(.pass))
        #expect(PhoneSelection(storageValue: "settings") == nil)
        #expect(PhoneSelection(storageValue: "nonsense") == nil)
        #expect(PhoneSelection.more.storageValue == "more")
        #expect(PhoneSelection.feature(.azan).storageValue == "azan")
    }
}
