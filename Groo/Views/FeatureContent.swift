//
//  FeatureContent.swift
//  Groo
//
//  Maps a TabID to its screen. The single place that mapping lives — both
//  MainTabView (iPad) and PhoneTabView (iPhone) consume it. Everything
//  returned here is stack-free: hosts supply the NavigationStack, so the same
//  screen renders correctly as a tab root or as a pushed More destination.
//

import SwiftUI

struct FeatureContent {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void
    let onLock: () -> Void

    @ViewBuilder
    func view(for tab: TabID) -> some View {
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
        case .azan:
            AzanView()
        case .stocks:
            StocksView()
        case .settings:
            SettingsView(
                padService: padService,
                passService: passService,
                onSignOut: onSignOut,
                onLock: onLock
            )
        }
    }
}
