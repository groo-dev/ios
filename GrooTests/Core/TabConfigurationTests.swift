//
//  TabConfigurationTests.swift
//  GrooTests
//
//  Invariants of the iPhone tab-bar configuration: the sanitizing init must
//  make an invalid configuration unrepresentable, so no consumer has to
//  defend against one.
//

import Foundation
import Testing
@testable import Groo

struct TabConfigurationTests {
    @Test func defaultPutsHomeAzanPassPadInTheBar() {
        #expect(TabConfiguration.default.barTabs == [.home, .azan, .pass, .pad])
    }

    @Test func defaultLeavesFourFeaturesInMore() {
        #expect(TabConfiguration.default.moreTabs == [.stocks, .crypto, .drive, .scratchpad])
    }

    @Test func settingsIsNeverOrderableAndNeverInTheBar() {
        let config = TabConfiguration(order: [.settings, .stocks], showsHome: true)
        #expect(!config.order.contains(.settings))
        #expect(!config.barTabs.contains(.settings))
        #expect(!config.moreTabs.contains(.settings))
    }

    @Test func homeIsNeverInTheOrderedList() {
        let config = TabConfiguration(order: [.home, .stocks], showsHome: true)
        #expect(!config.order.contains(.home))
    }

    @Test func disablingHomePromotesTheNextFeature() {
        var config = TabConfiguration.default
        config.setShowsHome(false)
        #expect(config.barTabs == [.azan, .pass, .pad, .stocks])
        #expect(config.moreTabs == [.crypto, .drive, .scratchpad])
    }

    @Test func duplicatesAreCollapsed() {
        let config = TabConfiguration(order: [.pass, .pass, .pad], showsHome: true)
        #expect(config.order.filter { $0 == .pass }.count == 1)
    }

    @Test func missingFeaturesAreAppendedInDefaultOrder() {
        let config = TabConfiguration(order: [.drive], showsHome: true)
        #expect(config.order.first == .drive)
        #expect(Set(config.order) == Set(TabConfiguration.reorderable))
    }

    @Test func orderAlwaysHoldsEverySevenReorderableFeatures() {
        let config = TabConfiguration(order: [], showsHome: false)
        #expect(config.order.count == 7)
    }

    @Test func moveReordersAndPreservesInvariants() {
        var config = TabConfiguration.default   // [azan, pass, pad, stocks, crypto, drive, scratchpad]
        config.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)   // drive to front
        #expect(config.order.first == .drive)
        #expect(config.barTabs == [.home, .drive, .azan, .pass])
        #expect(Set(config.order) == Set(TabConfiguration.reorderable))
    }

    @Test func decodingDropsUnknownIdentifiersAndRefills() throws {
        let json = #"{"order":["drive","not-a-tab","pass"],"showsHome":false}"#
        let config = try JSONDecoder().decode(TabConfiguration.self, from: Data(json.utf8))
        #expect(config.order.prefix(2) == [.drive, .pass])
        #expect(Set(config.order) == Set(TabConfiguration.reorderable))
        #expect(config.showsHome == false)
    }

    @Test func encodeDecodeRoundTrips() throws {
        var config = TabConfiguration.default
        config.move(fromOffsets: IndexSet(integer: 6), toOffset: 0)
        config.setShowsHome(false)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TabConfiguration.self, from: data)
        #expect(decoded == config)
    }
}
