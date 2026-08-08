//
//  PhoneTabView.swift
//  Groo
//
//  iPhone sibling of MainTabView. Four configurable feature tabs plus an
//  app-owned More tab, replacing the system overflow (a UIKit navigation
//  controller that silently discards SwiftUI's navigationTitle).
//
//  Deliberately NOT a parameterised version of MainTabView: the two roots
//  share only FeatureContent, so an iPhone change can never alter iPad.
//

import SwiftUI

struct PhoneTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @Environment(TabConfigurationStore.self) private var configStore
    @Environment(AppRouter.self) private var router

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

        return TabView(selection: $router.phoneSelection) {
            ForEach(configStore.configuration.barTabs, id: \.self) { tab in
                Tab(value: PhoneSelection.feature(tab)) {
                    NavigationStack { content.view(for: tab) }
                } label: {
                    tabLabel(for: tab)
                }
            }

            Tab(value: PhoneSelection.more) {
                MoreView(
                    configuration: configStore.configuration,
                    content: content,
                    path: $router.morePath
                )
            } label: {
                Label {
                    Text("More")
                } icon: {
                    Image(systemName: "ellipsis.circle")
                        .environment(\.symbolVariants, .none)
                }
            }
        }
        .modifier(TabBarMinimizeOnScrollModifier())
        .tint(Theme.Brand.primary)
        .onChange(of: configStore.configuration) {
            router.configurationDidChange()
        }
    }

    private func tabLabel(for tab: TabID) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
                .environment(\.symbolVariants, .none)
        }
    }
}
