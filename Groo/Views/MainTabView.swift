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
        case .home: "house"
        case .pad: "doc.on.clipboard"
        case .pass: "key"
        case .scratchpad: "note.text"
        case .drive: "folder"
        case .crypto: "wallet.bifold"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
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
            Tab("Home", systemImage: TabID.home.icon, value: TabID.home) {
                tabContent(for: .home)
            }
            .customizationID(TabID.home.rawValue)

            Tab("Stocks", systemImage: TabID.stocks.icon, value: TabID.stocks) {
                tabContent(for: .stocks)
            }
            .customizationID(TabID.stocks.rawValue)

            Tab("Wallet", systemImage: TabID.crypto.icon, value: TabID.crypto) {
                tabContent(for: .crypto)
            }
            .customizationID(TabID.crypto.rawValue)

            Tab("Pad", systemImage: TabID.pad.icon, value: TabID.pad) {
                tabContent(for: .pad)
            }
            .customizationID(TabID.pad.rawValue)

            Tab("Pass", systemImage: TabID.pass.icon, value: TabID.pass) {
                tabContent(for: .pass)
            }
            .customizationID(TabID.pass.rawValue)

            Tab("Drive", systemImage: TabID.drive.icon, value: TabID.drive) {
                tabContent(for: .drive)
            }
            .customizationID(TabID.drive.rawValue)

            Tab("Scratchpad", systemImage: TabID.scratchpad.icon, value: TabID.scratchpad) {
                tabContent(for: .scratchpad)
            }
            .customizationID(TabID.scratchpad.rawValue)

            Tab("Settings", systemImage: TabID.settings.icon, value: TabID.settings) {
                tabContent(for: .settings)
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
