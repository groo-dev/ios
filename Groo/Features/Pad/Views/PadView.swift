//
//  PadView.swift
//  Groo
//
//  Main Pad tab view with unlock and list.
//

import SwiftUI

struct PadView: View {
    let padService: PadService
    let syncService: SyncService
    let onSignOut: () -> Void

    @State private var showSettings = false
    @State private var showAddItem = false
    @State private var isUnlocked = false

    var body: some View {
        Group {
            if isUnlocked {
                unlockedView
            } else {
                PadUnlockView(
                    padService: padService,
                    syncService: syncService,
                    onUnlock: {
                        isUnlocked = true
                    },
                    onSignOut: onSignOut
                )
            }
        }
        .onAppear {
            isUnlocked = padService.isUnlocked
        }
    }

    private var unlockedView: some View {
        NavigationStack {
            PadListView(padService: padService, syncService: syncService)
                .navigationTitle("Pad")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddItem = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    PadSettingsView(
                        onLock: {
                            padService.lock()
                            isUnlocked = false
                        },
                        onSignOut: onSignOut
                    )
                }
                .sheet(isPresented: $showAddItem) {
                    AddItemSheet(padService: padService, syncService: syncService)
                }
        }
    }
}

#Preview {
    PadView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        onSignOut: {}
    )
    .environment(AuthService())
}
