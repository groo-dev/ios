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
        defaults.set("stocks", forKey: AppRouter.phoneSelectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func restoringHomeWhenHomeIsDisabledFallsBackToTheFirstBarTab() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(#"{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":false}"#,
                     forKey: TabConfigurationStore.defaultsKey)
        defaults.set("home", forKey: AppRouter.phoneSelectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.azan))
    }

    @Test func restoringMoreIsHonoured() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("more", forKey: AppRouter.phoneSelectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .more)
    }

    @Test func settingsIsNeverARestorableFeatureSelection() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("settings", forKey: AppRouter.phoneSelectionKey)

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

    // MARK: - Editor survival (More -> Settings -> Customize Tabs)
    //
    // The editor is reached by pushing .settings onto morePath, then a
    // view-based NavigationLink (Customize Tabs) on top of that — a push the
    // path array does not represent. Every drag or toggle in the editor
    // writes store.configuration, which fires configurationDidChange()
    // through PhoneTabView's onChange. Clearing morePath wholesale pops the
    // entire stack (Customize Tabs included) back to More's root; filtering
    // it to an equal array must not.

    @Test func configurationChangeWhileOnSettingsPreservesThePath() throws {
        let (router, store, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }
        router.morePath = [.settings]

        // Any edit reachable from the editor: toggling Home off and back on.
        var config = store.configuration
        config.setShowsHome(false)
        store.configuration = config
        router.configurationDidChange()

        #expect(router.morePath == [.settings])
    }

    @Test func configurationChangePreservesAPathEntryThatIsStillPastTheCut() throws {
        let (router, store, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }
        router.morePath = [.stocks]   // stocks is past the cut by default

        // Reorder drive/scratchpad against each other — stocks stays put.
        var config = store.configuration
        config.move(fromOffsets: IndexSet(integer: 6), toOffset: 5)
        #expect(config.moreTabs.contains(.stocks))
        store.configuration = config
        router.configurationDidChange()

        #expect(router.morePath == [.stocks])
    }

    @Test func configurationChangeDropsAPathEntryPromotedIntoTheBar() throws {
        let (router, store, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }
        router.morePath = [.stocks]   // stocks is past the cut by default

        // Drag stocks to the front — it is now a bar tab, not a More push.
        var config = store.configuration
        config.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(config.barTabs.contains(.stocks))
        store.configuration = config
        router.configurationDidChange()

        #expect(router.morePath.isEmpty)
    }

    @Test func selectionIsPersistedOnWrite() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(defaults.string(forKey: AppRouter.phoneSelectionKey) == "more")
    }

    @Test func padSelectionRestoresFromItsOwnKey() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("stocks", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.padSelection == .stocks)
    }

    @Test func padSelectionSurvivesAFreshRouterAfterOpeningAFeaturePastTheCut() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)   // stocks is past the phone's 4-slot cut

        let restored = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(restored.padSelection == .stocks)
        #expect(restored.phoneSelection == .more)
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
