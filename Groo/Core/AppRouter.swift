//
//  AppRouter.swift
//  Groo
//
//  Navigation intent, resolved against the live tab configuration. HomeView's
//  cards call open(_:) without knowing which idiom they are on or whether the
//  destination currently sits in the tab bar or inside More.
//
//  Both selections are maintained unconditionally: MainTabView (iPad) binds to
//  padSelection, PhoneTabView (iPhone) binds to phoneSelection/morePath. That
//  keeps every host free of idiom branching.
//

import Foundation
import Observation

/// What the iPhone tab bar currently has selected. Settings is deliberately
/// not representable — on iPhone it is a row inside More, never a tab.
enum PhoneSelection: Hashable {
    case feature(TabID)
    case more

    var storageValue: String {
        switch self {
        case .feature(let tab): tab.rawValue
        case .more: "more"
        }
    }

    init?(storageValue: String) {
        if storageValue == "more" {
            self = .more
        } else if let tab = TabID(rawValue: storageValue), tab != .settings {
            self = .feature(tab)
        } else {
            return nil
        }
    }
}

@Observable
@MainActor
final class AppRouter {
    /// The key the app has always used for iPad's selection, so a persisted
    /// value from before this feature — and UITest's `-selectedTab` override
    /// — still work.
    static let selectionKey = "selectedTab"

    /// iPhone's selection gets its own key. It encodes `PhoneSelection`
    /// (including the synthetic `"more"` case, which is not a `TabID`), so it
    /// cannot share `selectionKey` with `padSelection` without one clobbering
    /// the other on every write.
    static let phoneSelectionKey = "phoneSelectedTab"

    private let store: TabConfigurationStore
    private let defaults: UserDefaults

    var phoneSelection: PhoneSelection {
        didSet { defaults.set(phoneSelection.storageValue, forKey: Self.phoneSelectionKey) }
    }

    var padSelection: TabID {
        didSet { defaults.set(padSelection.rawValue, forKey: Self.selectionKey) }
    }

    var morePath: [TabID] = []

    init(store: TabConfigurationStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults

        let storedPhone = defaults.string(forKey: Self.phoneSelectionKey)
        let restored = storedPhone.flatMap(PhoneSelection.init(storageValue:))
        self.phoneSelection = Self.resolve(restored, in: store.configuration)

        let storedPad = defaults.string(forKey: Self.selectionKey)
        self.padSelection = storedPad.flatMap(TabID.init(rawValue:)) ?? .home
    }

    /// Navigate to a feature, wherever it currently lives.
    func open(_ tab: TabID) {
        padSelection = tab

        if store.configuration.barTabs.contains(tab) {
            morePath = []
            phoneSelection = .feature(tab)
        } else {
            phoneSelection = .more
            morePath = [tab]
        }
    }

    /// Called after the user edits the tab bar. The pushed destination may no
    /// longer belong inside More, and the selection may name a tab that is no
    /// longer on screen.
    func configurationDidChange() {
        morePath = []
        phoneSelection = Self.resolve(phoneSelection, in: store.configuration)
    }

    private static func resolve(_ selection: PhoneSelection?, in config: TabConfiguration) -> PhoneSelection {
        switch selection {
        case .more:
            return .more
        case .feature(let tab) where config.barTabs.contains(tab):
            return .feature(tab)
        default:
            // barTabs is never empty — order always holds all seven features —
            // so the fallback is defensive only.
            return config.barTabs.first.map(PhoneSelection.feature) ?? .more
        }
    }
}
