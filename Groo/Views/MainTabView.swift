//
//  MainTabView.swift
//  Groo
//
//  Tab-based navigation with customizable tab order.
//

import SwiftUI

enum TabID: String, CaseIterable, Codable {
    case pad, pass, scratchpad, drive, crypto, settings

    static let defaultOrder = "pad,pass,scratchpad,drive,crypto,settings"

    var title: String {
        switch self {
        case .pad: "Pad"
        case .pass: "Pass"
        case .scratchpad: "Scratchpad"
        case .drive: "Drive"
        case .crypto: "Wallet"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .pad: "doc.on.clipboard"
        case .pass: "key"
        case .scratchpad: "note.text"
        case .drive: "folder"
        case .crypto: "wallet.bifold"
        case .settings: "gearshape"
        }
    }

    static func fromStoredOrder(_ raw: String) -> [TabID] {
        let ids = raw.split(separator: ",").compactMap { TabID(rawValue: String($0)) }
        let missing = TabID.allCases.filter { !ids.contains($0) }
        return ids + missing
    }
}

struct MainTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @AppStorage("tabOrder") private var tabOrderRaw: String = TabID.defaultOrder

    private var tabOrder: [TabID] {
        TabID.fromStoredOrder(tabOrderRaw)
    }

    @ViewBuilder
    private func tabContent(for tab: TabID) -> some View {
        switch tab {
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
        TabView {
            ForEach(tabOrder, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon) {
                    tabContent(for: tab)
                }
            }
        }
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
