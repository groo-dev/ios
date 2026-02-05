//
//  MainTabView.swift
//  Groo
//
//  Tab-based navigation with customizable tabs and Liquid Glass support.
//

import SwiftUI

enum TabID: String, CaseIterable, Codable {
    case pad, scratchpad, pass, drive, crypto, settings

    var title: String {
        switch self {
        case .pad: "Pad"
        case .scratchpad: "Scratchpad"
        case .pass: "Pass"
        case .drive: "Drive"
        case .crypto: "Crypto"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .pad: "doc.on.clipboard"
        case .scratchpad: "note.text"
        case .pass: "key"
        case .drive: "folder"
        case .crypto: "bitcoinsign.circle"
        case .settings: "gearshape"
        }
    }
}

struct MainTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @AppStorage("tabOrder") private var tabOrderRaw: String = "pad,pass,scratchpad,drive,crypto,settings"
    @AppStorage("mainTabCount") private var mainTabCount: Int = 2

    private var tabOrder: [TabID] {
        let ids = tabOrderRaw.split(separator: ",").compactMap { TabID(rawValue: String($0)) }
        // Ensure all tabs are present (handle additions/removals gracefully)
        let missing = TabID.allCases.filter { !ids.contains($0) }
        return ids + missing
    }

    private var mainTabs: [TabID] {
        Array(tabOrder.prefix(mainTabCount))
    }

    private var moreTabs: [TabID] {
        Array(tabOrder.dropFirst(mainTabCount))
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
            CryptoPlaceholderView()
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
            ForEach(mainTabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon) {
                    tabContent(for: tab)
                }
            }

            Tab("More", systemImage: "ellipsis") {
                MoreTabView(
                    moreTabs: moreTabs,
                    padService: padService,
                    syncService: syncService,
                    passService: passService,
                    onSignOut: onSignOut
                )
            }

            Tab(role: .search) {
                NavigationStack {
                    Text("Search")
                        .navigationTitle("Search")
                }
            }
        }
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
