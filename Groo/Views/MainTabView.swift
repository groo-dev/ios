//
//  MainTabView.swift
//  Groo
//
//  Tab-based navigation with customizable tab order.
//

import SwiftUI

enum TabID: String, CaseIterable, Codable {
    case home, stocks, crypto, azan, pad, pass, drive, scratchpad, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .pad: "Pad"
        case .pass: "Pass"
        case .scratchpad: "Scratchpad"
        case .drive: "Drive"
        case .crypto: "Wallet"
        case .stocks: "Stocks"
        case .azan: "Azan"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "square.grid.2x2"
        case .pad: "list.bullet.rectangle"
        case .pass: "key.horizontal"
        case .scratchpad: "note.text"
        case .drive: "tray.2"
        case .crypto: "creditcard"
        case .stocks: "chart.xyaxis.line"
        case .azan: "moon.stars"
        case .settings: "gear"
        }
    }
}

struct MainTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @Environment(AppRouter.self) private var router
    @State private var customization = TabViewCustomization()

    private func tabLabel(for tab: TabID) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
                .environment(\.symbolVariants, .none)
        }
    }

    private var content: FeatureContent {
        FeatureContent(
            padService: padService,
            syncService: syncService,
            passService: passService,
            onSignOut: onSignOut,
            onLock: {
                padService.lock()
                passService.lock()
            }
        )
    }

    var body: some View {
        @Bindable var router = router

        return TabView(selection: $router.padSelection) {
            Tab(value: TabID.home) {
                NavigationStack { content.view(for: .home) }
            } label: {
                tabLabel(for: .home)
            }
            .customizationID(TabID.home.rawValue)

            Tab(value: TabID.stocks) {
                NavigationStack { content.view(for: .stocks) }
            } label: {
                tabLabel(for: .stocks)
            }
            .customizationID(TabID.stocks.rawValue)

            Tab(value: TabID.crypto) {
                NavigationStack { content.view(for: .crypto) }
            } label: {
                tabLabel(for: .crypto)
            }
            .customizationID(TabID.crypto.rawValue)

            Tab(value: TabID.azan) {
                NavigationStack { content.view(for: .azan) }
            } label: {
                tabLabel(for: .azan)
            }
            .customizationID(TabID.azan.rawValue)

            Tab(value: TabID.pad) {
                NavigationStack { content.view(for: .pad) }
            } label: {
                tabLabel(for: .pad)
            }
            .customizationID(TabID.pad.rawValue)

            Tab(value: TabID.pass) {
                NavigationStack { content.view(for: .pass) }
            } label: {
                tabLabel(for: .pass)
            }
            .customizationID(TabID.pass.rawValue)

            Tab(value: TabID.drive) {
                NavigationStack { content.view(for: .drive) }
            } label: {
                tabLabel(for: .drive)
            }
            .customizationID(TabID.drive.rawValue)

            Tab(value: TabID.scratchpad) {
                NavigationStack { content.view(for: .scratchpad) }
            } label: {
                tabLabel(for: .scratchpad)
            }
            .customizationID(TabID.scratchpad.rawValue)

            Tab(value: TabID.settings) {
                NavigationStack { content.view(for: .settings) }
            } label: {
                tabLabel(for: .settings)
            }
            .customizationID(TabID.settings.rawValue)
        }
        .tabViewCustomization($customization)
        .tabViewStyle(.sidebarAdaptable)
        .modifier(TabBarMinimizeOnScrollModifier())
        .tint(Theme.Brand.primary)
    }
}

struct TabBarMinimizeOnScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    let configStore = TabConfigurationStore()
    MainTabView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        passService: PassService(),
        onSignOut: {}
    )
    .environment(configStore)
    .environment(AppRouter(store: configStore))
}
