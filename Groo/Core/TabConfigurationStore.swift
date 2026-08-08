//
//  TabConfigurationStore.swift
//  Groo
//
//  Persists the iPhone tab-bar configuration. The value is a JSON *string*
//  rather than Data so that a UI test can seed it through NSArgumentDomain
//  (`-phoneTabBar '{"order":[…],"showsHome":true}'`), the same lever
//  UITestHelpers already uses for `-selectedTab`.
//

import Foundation
import Observation

@Observable
@MainActor
final class TabConfigurationStore {
    static let defaultsKey = "phoneTabBar"

    private let defaults: UserDefaults

    var configuration: TabConfiguration {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.configuration = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> TabConfiguration {
        guard let json = defaults.string(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(TabConfiguration.self, from: Data(json.utf8))
        else { return .default }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration),
              let json = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(json, forKey: Self.defaultsKey)
    }
}
