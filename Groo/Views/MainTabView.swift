//
//  MainTabView.swift
//  Groo
//
//  Tab-based navigation with Pad, Pass, and Drive tabs.
//

import SwiftUI

struct MainTabView: View {
    let padService: PadService
    let syncService: SyncService
    let onSignOut: () -> Void

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PadView(padService: padService, syncService: syncService, onSignOut: onSignOut)
                .tabItem {
                    Label("Pad", systemImage: "doc.on.clipboard")
                }
                .tag(0)

            PassPlaceholderView()
                .tabItem {
                    Label("Pass", systemImage: "key")
                }
                .tag(1)

            DrivePlaceholderView()
                .tabItem {
                    Label("Drive", systemImage: "folder")
                }
                .tag(2)
        }
        .tint(Theme.Brand.primary)
    }
}

#Preview {
    MainTabView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        onSignOut: {}
    )
}
