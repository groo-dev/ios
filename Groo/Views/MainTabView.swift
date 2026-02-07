//
//  MainTabView.swift
//  Groo
//
//  Tab-based navigation with customizable tab order.
//

import SwiftUI

enum TabID: String, CaseIterable, Codable {
    case home, stocks, crypto, pad, pass, drive, scratchpad, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .pad: "Pad"
        case .pass: "Pass"
        case .scratchpad: "Scratchpad"
        case .drive: "Drive"
        case .crypto: "Wallet"
        case .stocks: "Stocks"
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
        case .settings: "gear"
        }
    }
}

struct MainTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @AppStorage("selectedTab") private var selectedTab: TabID = .home
    @State private var customization = TabViewCustomization()

    private func tabLabel(for tab: TabID) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
                .environment(\.symbolVariants, .none)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TabID) -> some View {
        switch tab {
        case .home:
            HomeView(padService: padService, syncService: syncService, passService: passService)
        case .pad:
            PadView(padService: padService, syncService: syncService, onSignOut: onSignOut)
        case .pass:
            PassView(passService: passService, onSignOut: onSignOut)
        case .scratchpad:
            ScratchpadTabView(padService: padService, syncService: syncService)
        case .drive:
            DrivePlaceholderView()
        case .crypto:
            CryptoView(passService: passService)
        case .stocks:
            StocksView()
        case .settings:
            SettingsView(
                padService: padService,
                passService: passService,
                onSignOut: onSignOut,
                onLock: {
                    padService.lock()
                    passService.lock()
                }
            )
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: TabID.home) {
                tabContent(for: .home)
            } label: {
                tabLabel(for: .home)
            }
            .customizationID(TabID.home.rawValue)

            Tab(value: TabID.stocks) {
                tabContent(for: .stocks)
            } label: {
                tabLabel(for: .stocks)
            }
            .customizationID(TabID.stocks.rawValue)

            Tab(value: TabID.crypto) {
                tabContent(for: .crypto)
            } label: {
                tabLabel(for: .crypto)
            }
            .customizationID(TabID.crypto.rawValue)

            Tab(value: TabID.pad) {
                tabContent(for: .pad)
            } label: {
                tabLabel(for: .pad)
            }
            .customizationID(TabID.pad.rawValue)

            Tab(value: TabID.pass) {
                tabContent(for: .pass)
            } label: {
                tabLabel(for: .pass)
            }
            .customizationID(TabID.pass.rawValue)

            Tab(value: TabID.drive) {
                tabContent(for: .drive)
            } label: {
                tabLabel(for: .drive)
            }
            .customizationID(TabID.drive.rawValue)

            Tab(value: TabID.scratchpad) {
                tabContent(for: .scratchpad)
            } label: {
                tabLabel(for: .scratchpad)
            }
            .customizationID(TabID.scratchpad.rawValue)

            Tab(value: TabID.settings) {
                tabContent(for: .settings)
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

private struct TabBarMinimizeOnScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    MainTabView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        passService: PassService(),
        onSignOut: {}
    )
}
