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
    let passService: PassService
    let onSignOut: () -> Void

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PadView(padService: padService, syncService: syncService, onSignOut: onSignOut)
                .tabItem {
                    Label("Pad", systemImage: "doc.on.clipboard")
                }
                .tag(0)

            ScratchpadTabView(padService: padService, syncService: syncService)
                .tabItem {
                    Label("Scratchpad", systemImage: "note.text")
                }
                .tag(1)

            PassView(passService: passService, onSignOut: onSignOut)
                .tabItem {
                    Label("Pass", systemImage: "key")
                }
                .tag(2)

            DrivePlaceholderView()
                .tabItem {
                    Label("Drive", systemImage: "folder")
                }
                .tag(3)

            NavigationStack {
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
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(4)
        }
        .tint(Theme.Brand.primary)
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
