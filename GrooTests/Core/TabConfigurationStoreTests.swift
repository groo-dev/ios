//
//  TabConfigurationStoreTests.swift
//  GrooTests
//
//  Persistence for the iPhone tab bar. Stored as a JSON *string* so a UI test
//  can seed it through NSArgumentDomain. Every malformed input resolves to the
//  default rather than propagating a broken configuration.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct TabConfigurationStoreTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "tabconfig-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test func emptyStoreYieldsTheDefaultConfiguration() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TabConfigurationStore(defaults: defaults)

        #expect(store.configuration == .default)
    }

    @Test func writingPersistsAcrossStoreInstances() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TabConfigurationStore(defaults: defaults)
        var config = store.configuration
        config.setShowsHome(false)
        store.configuration = config

        let reloaded = TabConfigurationStore(defaults: defaults)

        #expect(reloaded.configuration.showsHome == false)
        #expect(reloaded.configuration.barTabs == [.azan, .pass, .pad, .stocks])
    }

    @Test func corruptJSONFallsBackToDefault() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("{ not json", forKey: TabConfigurationStore.defaultsKey)

        let store = TabConfigurationStore(defaults: defaults)

        #expect(store.configuration == .default)
    }

    @Test func partialJSONIsRepairedNotRejected() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(#"{"order":["drive"],"showsHome":true}"#, forKey: TabConfigurationStore.defaultsKey)

        let store = TabConfigurationStore(defaults: defaults)

        #expect(store.configuration.order.first == .drive)
        #expect(store.configuration.order.count == 7)
    }

    @Test func storedValueIsAStringSoLaunchArgumentsCanSeedIt() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TabConfigurationStore(defaults: defaults)
        var config = store.configuration
        config.setShowsHome(false)
        store.configuration = config

        #expect(defaults.string(forKey: TabConfigurationStore.defaultsKey) != nil)
    }
}
