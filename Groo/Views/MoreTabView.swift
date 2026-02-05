//
//  MoreTabView.swift
//  Groo
//
//  List of additional features accessible from the More tab.
//

import SwiftUI

struct MoreTabView: View {
    let moreTabs: [TabID]
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(moreTabs, id: \.self) { tab in
                    switch tab {
                    case .scratchpad:
                        NavigationLink {
                            ScratchpadTabView(padService: padService, syncService: syncService)
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    case .drive:
                        NavigationLink {
                            DrivePlaceholderView()
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    case .crypto:
                        NavigationLink {
                            CryptoPlaceholderView()
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    case .settings:
                        NavigationLink {
                            SettingsView(
                                padService: padService,
                                passService: passService,
                                onSignOut: onSignOut,
                                onLock: {
                                    padService.lock()
                                    passService.lock()
                                }
                            )
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    case .pad:
                        NavigationLink {
                            PadView(padService: padService, syncService: syncService, onSignOut: onSignOut)
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    case .pass:
                        NavigationLink {
                            PassView(passService: passService, onSignOut: onSignOut)
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    }
                }
            }
            .navigationTitle("More")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CustomizeTabsView()
                    } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .tint(Theme.Brand.primary)
    }
}

#Preview {
    MoreTabView(
        moreTabs: [.scratchpad, .drive, .crypto, .settings],
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        passService: PassService(),
        onSignOut: {}
    )
}
