//
//  MainTabView.swift
//  Groo
//
//  Tab-based navigation with customizable tabs and Liquid Glass support.
//

import SwiftUI

enum AppTab: String, Hashable {
    case pad, scratchpad, pass, drive, settings
}

struct MainTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @State private var selectedTab: AppTab = .pad
    @AppStorage("tabCustomization") var customization: TabViewCustomization

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Pad", systemImage: "doc.on.clipboard", value: .pad) {
                PadView(padService: padService, syncService: syncService, onSignOut: onSignOut)
            }
            .customizationID("pad")

            Tab("Scratchpad", systemImage: "note.text", value: .scratchpad) {
                ScratchpadTabView(padService: padService, syncService: syncService)
            }
            .customizationID("scratchpad")

            Tab("Pass", systemImage: "key", value: .pass) {
                PassView(passService: passService, onSignOut: onSignOut)
            }
            .customizationID("pass")

            Tab("Drive", systemImage: "folder", value: .drive) {
                DrivePlaceholderView()
            }
            .customizationID("drive")

            Tab("Settings", systemImage: "gearshape", value: .settings) {
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
            }
            .customizationID("settings")
            .customizationBehavior(.disabled, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
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
